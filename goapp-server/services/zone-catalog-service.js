'use strict';

const repo = require('../repositories/pg/pg-zone-catalog-repository');

class ZoneCatalogService {
  async listCatalog(filters = {}) {
    return repo.list(filters);
  }

  async resolveZoneByPoint(lat, lng) {
    return repo.resolveByPoint({ lat, lng });
  }
}

module.exports = new ZoneCatalogService();

