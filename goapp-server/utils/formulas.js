// GoApp Math Utilities - All formulas from Formula Reference V2

const config = require('../config');
const R = config.location.earthRadiusKm;

// ─── Degree / Radian Conversion ───
function toRad(deg) { return deg * (Math.PI / 180); }
function toDeg(rad) { return rad * (180 / Math.PI); }

// ═══════════════════════════════════════════
// FORMULA 01: Haversine Distance
// ═══════════════════════════════════════════
function haversine(lat1, lon1, lat2, lon2) {
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const rLat1 = toRad(lat1);
  const rLat2 = toRad(lat2);

  const a = Math.sin(dLat / 2) ** 2
          + Math.cos(rLat1) * Math.cos(rLat2) * Math.sin(dLon / 2) ** 2;
  const c = 2 * Math.asin(Math.sqrt(a));

  return R * c; // km
}

// ═══════════════════════════════════════════
// FORMULA 03: Bearing Between Two Points
// ═══════════════════════════════════════════
function bearing(lat1, lon1, lat2, lon2) {
  const rLat1 = toRad(lat1);
  const rLat2 = toRad(lat2);
  const dLon = toRad(lon2 - lon1);

  const x = Math.sin(dLon) * Math.cos(rLat2);
  const y = Math.cos(rLat1) * Math.sin(rLat2)
          - Math.sin(rLat1) * Math.cos(rLat2) * Math.cos(dLon);

  const bearingRad = Math.atan2(x, y);
  return (toDeg(bearingRad) + 360) % 360; // 0-360 degrees
}

// ═══════════════════════════════════════════
// FORMULA 04: Predictive Location Interpolation
// ═══════════════════════════════════════════
function predictLocation(lastLat, lastLng, speedMs, headingDeg, elapsedSec) {
  const headingRad = toRad(headingDeg);
  const predictedLat = lastLat + (speedMs * elapsedSec * Math.cos(headingRad)) / 111320;
  const predictedLng = lastLng + (speedMs * elapsedSec * Math.sin(headingRad)) / (111320 * Math.cos(toRad(lastLat)));

  return { lat: predictedLat, lng: predictedLng, interpolated: true };
}

// ═══════════════════════════════════════════
// FORMULA 02: Composite Driver Scoring
// ═══════════════════════════════════════════
function calculateCompositeScore(driver, riderLat, riderLng, maxETAInPool, precomputedEtaMin) {
  const W = config.scoring.weights;
  const F = config.scoring.freshness;
  const now = Date.now();

  // A. ETA Score — use precomputed ETA if available (avoids redundant haversine call)
  const distKm = precomputedEtaMin !== undefined
    ? (precomputedEtaMin / 60) * config.scoring.avgCitySpeedKmh
    : haversine(driver.lat, driver.lng, riderLat, riderLng);
  const etaMin = precomputedEtaMin !== undefined
    ? precomputedEtaMin
    : (distKm / config.scoring.avgCitySpeedKmh) * 60;
  const etaScore = maxETAInPool > 0 ? 1 - (etaMin / maxETAInPool) : 1;

  // B. Idle Score
  const lastTripEndTime = Number.isFinite(driver.lastTripEndTime) ? driver.lastTripEndTime : now;
  const idleMin = Math.max(0, (now - lastTripEndTime) / 60000);
  const maxIdleMinutes = Number.isFinite(config.scoring.maxIdleMinutes) && config.scoring.maxIdleMinutes > 0
    ? config.scoring.maxIdleMinutes
    : 1;
  const idleScore = Math.min(idleMin / maxIdleMinutes, 1.0);

  // C. Acceptance Rate Score
  const ridesOffered = Number.isFinite(driver.ridesOffered) ? driver.ridesOffered : 0;
  const ridesAccepted = Number.isFinite(driver.ridesAccepted) ? driver.ridesAccepted : 0;
  const acceptanceRaw = ridesOffered > 0 ? (ridesAccepted / ridesOffered) : 0.5;
  const acceptanceScore = Math.max(0, Math.min(1, acceptanceRaw));

  // D. Completion Rate Score
  const ridesCompleted = Number.isFinite(driver.ridesCompleted) ? driver.ridesCompleted : 0;
  const completionRaw = ridesAccepted > 0 ? (ridesCompleted / ridesAccepted) : 0.5;
  const completionScore = Math.max(0, Math.min(1, completionRaw));

  // E. Rating Score (normalized 1-5 → 0-1)
  const rating = Number.isFinite(driver.rating) ? driver.rating : 4.0;
  const ratingScore = Math.max(0, Math.min(1, (rating - 1.0) / 4.0));

  // F. Heading Score (cosine similarity)
  const bearingToRider = bearing(driver.lat, driver.lng, riderLat, riderLng);
  const heading = Number.isFinite(driver.heading) ? driver.heading : 0;
  const headingDiff = toRad(heading - bearingToRider);
  const headingScore = (1 + Math.cos(headingDiff)) / 2;

  // G. Freshness Modifier
  const lastLocationUpdate = Number.isFinite(driver.lastLocationUpdate) ? driver.lastLocationUpdate : now;
  const locationAge = Math.max(0, (now - lastLocationUpdate) / 1000);
  let freshnessModifier = 0;
  if (locationAge < F.boostThresholdSec) freshnessModifier = F.boostValue;
  else if (locationAge > F.penaltyThresholdSec) freshnessModifier = F.penaltyValue;

  // Composite Score
  const rawScore = (W.eta * Math.max(0, etaScore))
              + (W.idle * idleScore)
              + (W.acceptance * acceptanceScore)
              + (W.completion * completionScore)
              + (W.rating * ratingScore)
              + (W.heading * headingScore)
              + freshnessModifier;
  const score = Number.isFinite(rawScore) ? rawScore : 0;

  return {
    score: Math.round(score * 1000) / 1000,
    breakdown: {
      etaScore: Math.round(etaScore * 1000) / 1000,
      idleScore: Math.round(idleScore * 1000) / 1000,
      acceptanceScore: Math.round(acceptanceScore * 1000) / 1000,
      completionScore: Math.round(completionScore * 1000) / 1000,
      ratingScore: Math.round(ratingScore * 1000) / 1000,
      headingScore: Math.round(headingScore * 1000) / 1000,
      freshnessModifier,
    },
    distKm: Math.round(distKm * 100) / 100,
    etaMin: Math.round(etaMin * 10) / 10,
    locationAgeSec: Math.round(locationAge * 10) / 10,
  };
}

// ═══════════════════════════════════════════
// FORMULA 10: GPS Spoofing Detection
// ═══════════════════════════════════════════
function detectSpoofing(prevLocation, currLocation, timeDiffSec) {
  const distKm = haversine(prevLocation.lat, prevLocation.lng, currLocation.lat, currLocation.lng);
  const speedKmh = (distKm / timeDiffSec) * 3600;
  const jumpDistM = distKm * 1000;

  const flags = [];

  if (speedKmh > config.fraud.autoSuspendSpeedKmh) {
    flags.push({ type: 'AUTO_SUSPEND', reason: `Speed ${Math.round(speedKmh)} km/h > ${config.fraud.autoSuspendSpeedKmh} km/h` });
  } else if (speedKmh > config.fraud.maxSpeedKmh) {
    flags.push({ type: 'GPS_SPOOF_FLAG', reason: `Speed ${Math.round(speedKmh)} km/h > ${config.fraud.maxSpeedKmh} km/h` });
  }

  if (jumpDistM > config.fraud.jumpDistanceM && timeDiffSec < config.fraud.jumpTimeSec) {
    flags.push({ type: 'LOCATION_JUMP', reason: `Jumped ${Math.round(jumpDistM)}m in ${timeDiffSec}s` });
  }

  return {
    isSuspicious: flags.length > 0,
    speedKmh: Math.round(speedKmh),
    jumpDistM: Math.round(jumpDistM),
    flags,
  };
}

function detectRouteInflation(pickupLat, pickupLng, dropoffLat, dropoffLng, actualRouteKm) {
  const straightLineKm = haversine(pickupLat, pickupLng, dropoffLat, dropoffLng);
  const efficiency = straightLineKm / actualRouteKm;

  return {
    straightLineKm: Math.round(straightLineKm * 100) / 100,
    actualRouteKm,
    efficiency: Math.round(efficiency * 1000) / 1000,
    isFlagged: efficiency < config.fraud.minRouteEfficiency,
  };
}

module.exports = {
  haversine, bearing, predictLocation, calculateCompositeScore,
  detectSpoofing, detectRouteInflation, toRad, toDeg,
};
