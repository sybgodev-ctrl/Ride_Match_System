'use strict';

const repo = require('../repositories/pg/pg-zone-catalog-repository');

class ZoneMappingService {
  async resolveZoneByPoint(lat, lng) {
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
    return repo.resolveByPoint({ lat, lng });
  }

  async resolvePickupAndDrop(pickupLat, pickupLng, dropLat, dropLng) {
    const [pickupZone, dropZone] = await Promise.all([
      this.resolveZoneByPoint(pickupLat, pickupLng),
      this.resolveZoneByPoint(dropLat, dropLng),
    ]);
    return {
      pickupZoneId: pickupZone?.id || null,
      pickupZoneCode: pickupZone?.zoneCode || null,
      dropZoneId: dropZone?.id || null,
      dropZoneCode: dropZone?.zoneCode || null,
    };
  }
}

module.exports = new ZoneMappingService();

