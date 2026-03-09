const test = require('node:test');
const assert = require('node:assert/strict');

const zoneMappingService = require('../services/zone-mapping-service');
const zoneCatalogRepo = require('../repositories/pg/pg-zone-catalog-repository');

test('zone mapping returns null when coordinates invalid', async () => {
  const zone = await zoneMappingService.resolveZoneByPoint(NaN, 80.27);
  assert.equal(zone, null);
});

test('zone mapping resolves pickup and drop ids from repo', async () => {
  const originalResolve = zoneCatalogRepo.resolveByPoint;
  let call = 0;
  zoneCatalogRepo.resolveByPoint = async () => {
    call += 1;
    return call === 1
      ? { id: 'pickup-zone', zoneCode: 'CHN-CENTRAL' }
      : { id: 'drop-zone', zoneCode: 'CHN-ADYAR' };
  };

  const result = await zoneMappingService.resolvePickupAndDrop(
    13.0827, 80.2707, 13.0012, 80.2565,
  );
  zoneCatalogRepo.resolveByPoint = originalResolve;

  assert.equal(result.pickupZoneId, 'pickup-zone');
  assert.equal(result.dropZoneId, 'drop-zone');
  assert.equal(result.pickupZoneCode, 'CHN-CENTRAL');
  assert.equal(result.dropZoneCode, 'CHN-ADYAR');
});

