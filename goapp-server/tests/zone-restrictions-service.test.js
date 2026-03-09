const test = require('node:test');
const assert = require('node:assert/strict');

const service = require('../services/zone-restrictions-service');
const repo = require('../repositories/pg/pg-zone-restrictions-repository');
const googleMapsService = require('../services/google-maps-service');

test('zone restriction service fails open when reverse geocode is unavailable', async () => {
  const originalReverseGeocode = googleMapsService.reverseGeocode;
  const originalCheckCoordinate = repo.checkCoordinate;

  googleMapsService.reverseGeocode = async () => ({ error: 'maps down' });
  let repoCalled = false;
  repo.checkCoordinate = async () => {
    repoCalled = true;
    return { restricted: true };
  };

  const result = await service.checkRestricted(13.0827, 80.2707, 'rider');

  googleMapsService.reverseGeocode = originalReverseGeocode;
  repo.checkCoordinate = originalCheckCoordinate;

  assert.equal(repoCalled, false);
  assert.equal(result.restricted, false);
  assert.equal(result.geocodeUnavailable, true);
});

test('zone restriction service resolves location and forwards normalized values to repo', async () => {
  const originalReverseGeocode = googleMapsService.reverseGeocode;
  const originalCheckCoordinate = repo.checkCoordinate;

  googleMapsService.reverseGeocode = async () => ({
    formattedAddress: 'Chennai',
    country: 'in',
    state: 'tn',
    pincode: '600001',
  });

  let capturedLocation = null;
  repo.checkCoordinate = async (lat, lng, role, location) => {
    capturedLocation = location;
    return { restricted: false, location };
  };

  const result = await service.checkRestricted(13.0827, 80.2707, 'rider');

  googleMapsService.reverseGeocode = originalReverseGeocode;
  repo.checkCoordinate = originalCheckCoordinate;

  assert.equal(result.restricted, false);
  assert.equal(capturedLocation.country, 'IN');
  assert.equal(capturedLocation.state, 'TN');
  assert.equal(capturedLocation.pincode, '600001');
});

