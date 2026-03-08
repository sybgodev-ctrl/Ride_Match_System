// PostgreSQL-backed Ride Repository
// Tables: rides, ride_status_history
// Used by ride-service.js when DB_BACKEND=pg

'use strict';

const db = require('../../services/db');

class PgRideRepository {
  // ─── Create ───────────────────────────────────────────────────────────────

  async createRide({
    rideId, riderId, rideType,
    pickupLat, pickupLng, destLat, destLng,
    fareEstimate, surgeMultiplier, idempotencyKey,
  }) {
    const client = await db.getClient();
    try {
      await client.query('BEGIN');

      // riderId is the users.id UUID; resolve to riders.id
      const { rows: riderRows } = await client.query(
        `SELECT id FROM riders WHERE user_id = $1 LIMIT 1`,
        [riderId]
      );
      if (!riderRows.length) {
        throw new Error(`Rider record not found for user ${riderId}. Complete rider onboarding first.`);
      }
      const dbRiderId = riderRows[0].id;

      const { rows } = await client.query(
        `INSERT INTO rides
           (id, ride_number, rider_id, ride_type,
            pickup_lat, pickup_lng, dropoff_lat, dropoff_lng,
            estimated_fare, surge_multiplier, status, idempotency_key)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 'requested', $11)
         RETURNING id, ride_number, status,
                   EXTRACT(EPOCH FROM created_at) * 1000 AS "createdAt"`,
        [
          rideId, rideId, dbRiderId, rideType,
          pickupLat, pickupLng, destLat, destLng,
          fareEstimate, surgeMultiplier, idempotencyKey || null,
        ]
      );

      await client.query(
        `INSERT INTO ride_status_history (ride_id, status) VALUES ($1, 'requested')`,
        [rideId]
      );

      await client.query('COMMIT');
      return rows[0];
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  // ─── Read ─────────────────────────────────────────────────────────────────

  async getRide(rideId) {
    const { rows } = await db.query(
      `SELECT r.id AS "rideId", r.ride_number, r.status,
              r.pickup_lat AS "pickupLat", r.pickup_lng AS "pickupLng",
              r.dropoff_lat AS "destLat", r.dropoff_lng AS "destLng",
              r.ride_type AS "rideType",
              r.estimated_fare AS "estimatedFare", r.actual_fare AS "finalFare",
              r.surge_multiplier AS "surgeMultiplier",
              r.idempotency_key AS "idempotencyKey",
              u.id AS "riderId",
              EXTRACT(EPOCH FROM r.accepted_at)   * 1000 AS "acceptedAt",
              EXTRACT(EPOCH FROM r.started_at)    * 1000 AS "startedAt",
              EXTRACT(EPOCH FROM r.completed_at)  * 1000 AS "completedAt",
              EXTRACT(EPOCH FROM r.cancelled_at)  * 1000 AS "cancelledAt",
              EXTRACT(EPOCH FROM r.created_at)    * 1000 AS "createdAt"
       FROM rides r
       JOIN riders ri ON ri.id = r.rider_id
       JOIN users  u  ON u.id  = ri.user_id
       WHERE r.id = $1`,
      [rideId]
    );
    return rows[0] || null;
  }

  async getAllRides(limit = 200) {
    const { rows } = await db.query(
      `SELECT id AS "rideId", status, ride_type AS "rideType",
              COALESCE(actual_fare, estimated_fare) AS fare,
              EXTRACT(EPOCH FROM created_at) * 1000 AS "createdAt"
       FROM rides ORDER BY created_at DESC LIMIT $1`,
      [limit]
    );
    return rows;
  }

  async getRideByIdempotencyKey(key) {
    const { rows } = await db.query(
      `SELECT id AS "rideId", status FROM rides WHERE idempotency_key = $1`,
      [key]
    );
    return rows[0] || null;
  }

  // ─── Update ───────────────────────────────────────────────────────────────

  async updateStatus(rideId, status, extra = {}) {
    const {
      driverDbId, acceptedAt, startedAt, completedAt,
      cancelledAt, cancelledBy, finalFare, actualDistanceM, actualDurationS,
    } = extra;

    const { rows } = await db.query(
      `UPDATE rides SET
         status       = $2,
         driver_id    = COALESCE($3, driver_id),
         accepted_at  = COALESCE($4, accepted_at),
         started_at   = COALESCE($5, started_at),
         completed_at = COALESCE($6, completed_at),
         cancelled_at = COALESCE($7, cancelled_at),
         actual_fare  = COALESCE($8, actual_fare),
         actual_distance_m  = COALESCE($9,  actual_distance_m),
         actual_duration_s  = COALESCE($10, actual_duration_s),
         updated_at   = NOW()
       WHERE id = $1
       RETURNING id, status`,
      [
        rideId, status,
        driverDbId   || null,
        acceptedAt   ? new Date(acceptedAt)   : null,
        startedAt    ? new Date(startedAt)    : null,
        completedAt  ? new Date(completedAt)  : null,
        cancelledAt  ? new Date(cancelledAt)  : null,
        finalFare    || null,
        actualDistanceM  || null,
        actualDurationS  || null,
      ]
    );

    // Append to history (non-fatal)
    db.query(
      `INSERT INTO ride_status_history (ride_id, status) VALUES ($1, $2)`,
      [rideId, status]
    ).catch(() => {});

    return rows[0] || null;
  }

  // Resolve driver external_id → DB UUID for FK usage
  async resolveDriverDbId(driverExternalId) {
    const { rows } = await db.query(
      `SELECT d.id FROM drivers d
       JOIN users u ON u.id = d.user_id
       WHERE u.id = $1
         OR d.id::text = $1
       LIMIT 1`,
      [driverExternalId]
    );
    return rows[0]?.id || null;
  }

  // ─── Stats ────────────────────────────────────────────────────────────────

  async getStats() {
    const { rows } = await db.query(
      `SELECT
         COUNT(*)                                                           AS "totalRides",
         COUNT(*) FILTER (WHERE status = 'completed')                      AS "completedRides",
         COALESCE(SUM(actual_fare) FILTER (WHERE status = 'completed'), 0) AS "totalRevenue",
         COALESCE(
           AVG(EXTRACT(EPOCH FROM (accepted_at - requested_at)))
           FILTER (WHERE accepted_at IS NOT NULL), 0
         )                                                                  AS "avgMatchTimeSec"
       FROM rides`
    );
    const r = rows[0];
    return {
      totalRides:       parseInt(r.totalRides),
      completedRides:   parseInt(r.completedRides),
      totalRevenue:     `₹${parseFloat(r.totalRevenue).toFixed(2)}`,
      avgMatchTimeSec:  Math.round(parseFloat(r.avgMatchTimeSec)),
    };
  }
}

module.exports = new PgRideRepository();
