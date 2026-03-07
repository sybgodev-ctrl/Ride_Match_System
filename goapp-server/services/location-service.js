// GoApp Driver Location Service
// Manages real-time driver positions in Redis GEO.
//
// DB_BACKEND=pg  → additionally writes to PostGIS driver_locations table
//                  (persistence + history) and falls back to PostGIS spatial
//                  search when Redis GEO returns no results.

const redis  = require('./redis-client');
const config = require('../config');
const { predictLocation, detectSpoofing } = require('../utils/formulas');
const { logger, eventBus } = require('../utils/logger');

const USE_PG = config.db.backend === 'pg';
const pgRepo = USE_PG ? require('../repositories/pg/pg-location-repository') : null;

const GEO_KEY = 'drivers:locations';
const driverMeta = new Map(); // driverId -> { speed, heading, prevLocation, jumpCount, ... }

// Evict stale entries every 5 minutes to prevent unbounded Map growth.
// Entries older than maxAgeSec are considered gone and removed.
const _evictTimer = setInterval(() => {
  const maxAgeMs = (config.scoring?.freshness?.maxAgeSec ?? 300) * 1000;
  const cutoff = Date.now() - maxAgeMs;
  for (const [driverId, meta] of driverMeta) {
    if (meta.updatedAt < cutoff) {
      driverMeta.delete(driverId);
      logger.info('LOCATION', `Evicted stale driver ${driverId} from location cache`);
    }
  }
}, 5 * 60 * 1000);
_evictTimer.unref();

class LocationService {
  // Process incoming GPS update from driver
  updateLocation(driverId, { lat, lng, speed, heading, clientTimestamp }) {
    const now = Date.now();
    const prev = driverMeta.get(driverId);

    // ─── Fraud Detection ───
    if (prev && prev.lat && prev.lng) {
      const timeDiff = (now - prev.updatedAt) / 1000;
      if (timeDiff > 0) {
        const spoofCheck = detectSpoofing(
          { lat: prev.lat, lng: prev.lng },
          { lat, lng },
          timeDiff
        );

        if (spoofCheck.isSuspicious) {
          for (const flag of spoofCheck.flags) {
            logger.error('LOCATION', `Fraud detected for driver ${driverId}: ${flag.reason}`);
            eventBus.publish('fraud_alert_triggered', {
              driverId,
              type: flag.type,
              reason: flag.reason,
              speedKmh: spoofCheck.speedKmh,
            });

            if (flag.type === 'AUTO_SUSPEND') {
              return { success: false, reason: 'SUSPENDED', flag };
            }
          }

          // Track jump count
          const meta = driverMeta.get(driverId) || {};
          meta.jumpCount = (meta.jumpCount || 0) + 1;
          if (meta.jumpCount > config.fraud.maxJumpsIn10Min) {
            logger.error('LOCATION', `Driver ${driverId} suspended: ${meta.jumpCount} location jumps`);
            return { success: false, reason: 'JUMP_LIMIT_EXCEEDED' };
          }
        }
      }
    }

    // ─── Store in Redis GEO ───
    redis.geoadd(GEO_KEY, lng, lat, driverId);

    // ─── Persist to PostGIS (async, non-blocking) ───
    if (USE_PG) {
      pgRepo.recordLocation(driverId, { lat, lng, speed, heading })
        .catch(err => logger.warn('LOCATION', `PostGIS write failed (non-fatal): ${err.message}`));
    }

    // ─── Update metadata ───
    driverMeta.set(driverId, {
      lat, lng, speed: speed || 0, heading: heading || 0,
      updatedAt: now,
      prevLat: prev?.lat, prevLng: prev?.lng,
      jumpCount: prev?.jumpCount || 0,
    });

    // Publish location event
    eventBus.publish('driver_location_update', {
      driverId, lat, lng, speed, heading, timestamp: now,
    });

    return { success: true, lat, lng };
  }

  // Get driver's current position (with staleness handling)
  getDriverLocation(driverId) {
    const meta = driverMeta.get(driverId);
    if (!meta) return null;

    const age = (Date.now() - meta.updatedAt) / 1000;

    // Expired - too stale
    if (age > config.scoring.freshness.maxAgeSec) {
      return { ...meta, stale: true, expired: true, ageSec: Math.round(age) };
    }

    // Needs interpolation
    if (age > config.scoring.freshness.boostThresholdSec && meta.speed > 0) {
      const predicted = predictLocation(meta.lat, meta.lng, meta.speed, meta.heading, age);
      return {
        ...predicted, speed: meta.speed, heading: meta.heading,
        stale: true, expired: false, interpolated: true, ageSec: Math.round(age),
      };
    }

    // Fresh
    return { ...meta, stale: false, expired: false, ageSec: Math.round(age) };
  }

  // Find nearby drivers using GEORADIUS (Redis primary, PostGIS fallback)
  async findNearby(lat, lng, radiusKm, maxCount) {
    const results = redis.georadius(GEO_KEY, lng, lat, radiusKm, { count: maxCount * 3 });

    // Filter out stale drivers from Redis result
    const fresh = results.filter(r => {
      const meta = driverMeta.get(r.member);
      if (!meta) return false;
      return (Date.now() - meta.updatedAt) / 1000 <= config.scoring.freshness.maxAgeSec;
    }).map(r => {
      const meta = driverMeta.get(r.member);
      return {
        driverId:   r.member,
        lat:        r.lat,
        lng:        r.lng,
        distance:   r.distance,
        speed:      meta?.speed   || 0,
        heading:    meta?.heading || 0,
        lastUpdate: meta?.updatedAt,
        ageSec:     meta ? Math.round((Date.now() - meta.updatedAt) / 1000) : 999,
      };
    });

    // PostGIS fallback when Redis returns nothing (e.g. Redis cleared/restart)
    if (fresh.length === 0 && USE_PG) {
      logger.info('LOCATION', `Redis GEO empty — falling back to PostGIS spatial query`);
      const pgResults = await pgRepo.findNearbyDrivers(lat, lng, radiusKm, maxCount);
      return pgResults.map(r => ({
        driverId:   r.driverId,
        lat:        r.lat,
        lng:        r.lng,
        distance:   r.distanceKm,
        speed:      r.speed || 0,
        heading:    r.heading || 0,
        lastUpdate: r.lastUpdate,
        ageSec:     Math.round((Date.now() - new Date(r.lastUpdate).getTime()) / 1000),
      }));
    }

    return fresh;
  }

  // Remove driver from location tracking (went offline)
  removeDriver(driverId) {
    redis.georemove(GEO_KEY, driverId);
    driverMeta.delete(driverId);
    if (USE_PG) pgRepo.removeDriverLocation(driverId).catch(() => {});
    logger.info('LOCATION', `Driver ${driverId} removed from tracking`);
  }

  // Get all tracked drivers
  getAllTracked() {
    const all = [];
    for (const [driverId, meta] of driverMeta) {
      all.push({
        driverId,
        lat: meta.lat,
        lng: meta.lng,
        speed: meta.speed,
        heading: meta.heading,
        ageSec: Math.round((Date.now() - meta.updatedAt) / 1000),
      });
    }
    return all;
  }

  async getStats() {
    const base = {
      trackedDrivers:  driverMeta.size,
      redisGeoMembers: redis.geoSets?.get(GEO_KEY)?.size || 0,
    };
    if (USE_PG) {
      const pgStats = await pgRepo.getStats().catch(() => ({}));
      return { ...base, ...pgStats };
    }
    return base;
  }
}

module.exports = new LocationService();
