// GoApp Mock Database
// In-memory repository for development (mock mode).
// In pg mode, delegates read operations to pg-driver-repository.
//
// DB_BACKEND=mock  → in-memory Maps seeded from test-data.js (zero setup)
// DB_BACKEND=pg    → reads from PostgreSQL drivers/riders tables

const config = require('../config');
const { generateDrivers, generateRiders } = require('../data/test-data');

const USE_PG = config.db.backend === 'pg';
const pgRepo = USE_PG ? require('../repositories/pg/pg-driver-repository') : null;

class MockDb {
  constructor() {
    this.drivers  = new Map();
    this.riders   = new Map();
    this.seedMeta = null;
  }

  // Seed in-memory Maps (mock mode) or log a no-op (pg mode).
  // Returns the seeded data so server.js can register drivers with the matching engine.
  seed({ driverCount = 20, riderCount = 10, driverSeed = 42, riderSeed = 99 } = {}) {
    if (USE_PG) {
      // In pg mode we don't seed in-memory — real data lives in PostgreSQL.
      // Return empty arrays; the matching engine will populate from DB.
      this.seedMeta = { seededAt: Date.now(), driverCount: 0, riderCount: 0, pg: true };
      return { drivers: [], riders: [], ...this.seedMeta };
    }

    const drivers = generateDrivers(driverCount, driverSeed);
    const riders  = generateRiders(riderCount,  riderSeed);

    this.drivers.clear();
    this.riders.clear();
    for (const d of drivers) this.drivers.set(d.driverId, { ...d });
    for (const r of riders)  this.riders.set(r.riderId,   { ...r });

    this.seedMeta = { seededAt: Date.now(), driverCount, riderCount, driverSeed, riderSeed };
    return { drivers, riders, ...this.seedMeta };
  }

  async listDrivers() {
    if (USE_PG) return pgRepo.listDrivers();
    return [...this.drivers.values()];
  }

  async listRiders() {
    if (USE_PG) return pgRepo.listRiders();
    return [...this.riders.values()];
  }

  async getRider(riderId) {
    if (USE_PG) return pgRepo.getRider(riderId);
    return this.riders.get(riderId) || null;
  }

  async updateRiderRating(riderId, newRating) {
    if (USE_PG) return pgRepo.updateRiderRating(riderId, newRating);
    const rider = this.riders.get(riderId);
    if (rider) rider.rating = newRating;
  }

  async getStats() {
    if (USE_PG) return pgRepo.getStats();
    return { driverRecords: this.drivers.size, riderRecords: this.riders.size, seedMeta: this.seedMeta };
  }
}

module.exports = new MockDb();
