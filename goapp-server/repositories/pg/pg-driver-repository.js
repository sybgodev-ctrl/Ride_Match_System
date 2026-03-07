// PostgreSQL-backed Driver & Rider Repository
// Tables: drivers, riders, users, user_profiles, vehicles, vehicle_types
// Used by mock-db.js when DB_BACKEND=pg

'use strict';

const db = require('../../services/db');

class PgDriverRepository {
  // ─── Drivers ──────────────────────────────────────────────────────────────

  async listDrivers(limit = 100) {
    const { rows } = await db.query(
      `SELECT
         d.id                                                       AS "driverId",
         u.id                                                       AS "userId",
         COALESCE(up.display_name,
           up.first_name || ' ' || up.last_name, u.phone_number)   AS name,
         d.onboarding_status                                        AS status,
         d.is_eligible,
         d.home_city,
         v.vehicle_number                                           AS "vehicleNumber",
         vt.name                                                    AS "vehicleType",
         COALESCE(dr.average_rating, 5.0)                          AS rating,
         COALESCE(dr.acceptance_rate, 1.0)                         AS "acceptanceRate",
         COALESCE(dr.completion_rate, 1.0)                         AS "completionRate"
       FROM drivers d
       JOIN users u          ON u.id = d.user_id
       LEFT JOIN user_profiles up ON up.user_id = u.id
       LEFT JOIN vehicles v       ON v.driver_id = d.id AND v.is_primary = true
       LEFT JOIN vehicle_types vt ON vt.id = v.vehicle_type_id
       LEFT JOIN driver_ratings dr ON dr.driver_id = d.id
       WHERE d.onboarding_status = 'approved'
         AND u.deleted_at IS NULL
       ORDER BY d.created_at DESC LIMIT $1`,
      [limit]
    );
    return rows;
  }

  async getDriver(driverId) {
    const { rows } = await db.query(
      `SELECT
         d.id                                                       AS "driverId",
         u.id                                                       AS "userId",
         COALESCE(up.display_name,
           up.first_name || ' ' || up.last_name, u.phone_number)   AS name,
         d.onboarding_status                                        AS status,
         d.is_eligible,
         v.vehicle_number                                           AS "vehicleNumber",
         vt.name                                                    AS "vehicleType",
         COALESCE(dr.average_rating, 5.0)                          AS rating,
         COALESCE(dr.acceptance_rate, 1.0)                         AS "acceptanceRate",
         COALESCE(dr.completion_rate, 1.0)                         AS "completionRate"
       FROM drivers d
       JOIN users u          ON u.id = d.user_id
       LEFT JOIN user_profiles up ON up.user_id = u.id
       LEFT JOIN vehicles v       ON v.driver_id = d.id AND v.is_primary = true
       LEFT JOIN vehicle_types vt ON vt.id = v.vehicle_type_id
       LEFT JOIN driver_ratings dr ON dr.driver_id = d.id
       WHERE d.id::text = $1 OR u.id::text = $1
       LIMIT 1`,
      [driverId]
    );
    return rows[0] || null;
  }

  async updateDriverStatus(driverId, status) {
    // status here maps to onboarding_status or is_eligible flag
    const isAvailabilityStatus = ['online', 'offline', 'busy'].includes(status);

    if (isAvailabilityStatus) {
      // Track availability via driver_availability table if it exists, else no-op
      await db.query(
        `INSERT INTO driver_availability (driver_id, is_online, updated_at)
         VALUES ($1, $2, NOW())
         ON CONFLICT (driver_id)
         DO UPDATE SET is_online = $2, updated_at = NOW()`,
        [driverId, status === 'online']
      ).catch(() => {}); // non-fatal if table doesn't exist yet
    } else {
      await db.query(
        `UPDATE drivers SET onboarding_status = $2, updated_at = NOW()
         WHERE id::text = $1`,
        [driverId, status]
      );
    }
  }

  async updateDriverRating(driverId, newRating) {
    await db.query(
      `INSERT INTO driver_ratings (driver_id, average_rating)
       VALUES ($1, $2)
       ON CONFLICT (driver_id)
       DO UPDATE SET average_rating = $2, updated_at = NOW()`,
      [driverId, newRating]
    ).catch(() => {}); // non-fatal if table doesn't exist yet
  }

  // ─── Riders ───────────────────────────────────────────────────────────────

  async listRiders(limit = 100) {
    const { rows } = await db.query(
      `SELECT
         r.id                                                        AS "riderId",
         u.id                                                        AS "userId",
         COALESCE(up.display_name,
           up.first_name || ' ' || up.last_name, u.phone_number)    AS name,
         u.status,
         r.total_rides                                               AS "totalRides",
         r.lifetime_spend                                            AS "lifetimeSpend",
         r.rider_tier                                                AS "riderTier"
       FROM riders r
       JOIN users u          ON u.id = r.user_id
       LEFT JOIN user_profiles up ON up.user_id = u.id
       WHERE u.deleted_at IS NULL
       ORDER BY r.created_at DESC LIMIT $1`,
      [limit]
    );
    return rows;
  }

  async getRider(riderId) {
    const { rows } = await db.query(
      `SELECT
         r.id                                                        AS "riderId",
         u.id                                                        AS "userId",
         COALESCE(up.display_name,
           up.first_name || ' ' || up.last_name, u.phone_number)    AS name,
         u.status,
         r.total_rides                                               AS "totalRides"
       FROM riders r
       JOIN users u          ON u.id = r.user_id
       LEFT JOIN user_profiles up ON up.user_id = u.id
       WHERE r.id::text = $1 OR u.id::text = $1
       LIMIT 1`,
      [riderId]
    );
    return rows[0] || null;
  }

  async updateRiderRating(riderId, newRating) {
    await db.query(
      `INSERT INTO rider_ratings (rider_id, rating, ride_id, driver_id)
       VALUES ($1, $2, gen_random_uuid(), gen_random_uuid())
       ON CONFLICT DO NOTHING`,
      [riderId, newRating]
    ).catch(() => {});
  }

  // ─── Stats ────────────────────────────────────────────────────────────────

  async getStats() {
    const [{ rows: dr }, { rows: rr }] = await Promise.all([
      db.query(`SELECT COUNT(*)::int AS cnt FROM drivers WHERE onboarding_status = 'approved'`),
      db.query(`SELECT COUNT(*)::int AS cnt FROM riders`),
    ]);
    return {
      driverRecords: dr[0].cnt,
      riderRecords:  rr[0].cnt,
    };
  }
}

module.exports = new PgDriverRepository();
