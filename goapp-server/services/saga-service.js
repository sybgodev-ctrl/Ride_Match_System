// GoApp Saga Orchestration Service
//
// Implements the Saga pattern for distributed transaction management.
// Each saga tracks a multi-step business flow (ride lifecycle, payment,
// refund, driver payout) and provides compensating transactions on failure.
//
// Tables: saga_instances, saga_step_logs, saga_compensations, dead_letter_events
// DB_BACKEND=mock  → in-memory Maps (saga state still tracked, but not persisted)
// DB_BACKEND=pg    → full PostgreSQL persistence

'use strict';

const crypto = require('crypto');
const config = require('../config');
const db     = require('./db');
const { logger, eventBus } = require('../utils/logger');

const USE_PG = config.db.backend === 'pg';

// ─── In-Memory Saga Store (mock / fallback) ───────────────────────────────────

class InMemorySagaStore {
  constructor() {
    this.sagas = new Map(); // sagaId → saga object
  }

  async create(sagaType, correlationId, stateData, timeoutMs = 300_000) {
    const saga = {
      id:            crypto.randomUUID(),
      sagaType,
      correlationId,
      currentStep:   'init',
      status:        'running',
      stateData,
      steps:         [],
      startedAt:     Date.now(),
      timeoutAt:     Date.now() + timeoutMs,
    };
    this.sagas.set(saga.id, saga);
    return saga;
  }

  async updateStep(sagaId, step, status, output, error) {
    const saga = this.sagas.get(sagaId);
    if (!saga) throw new Error(`Saga ${sagaId} not found`);
    saga.currentStep = step;
    saga.steps.push({ step, status, output, error, at: Date.now() });
    return saga;
  }

  async complete(sagaId, finalStatus, stateData) {
    const saga = this.sagas.get(sagaId);
    if (!saga) throw new Error(`Saga ${sagaId} not found`);
    saga.status      = finalStatus;
    saga.stateData   = { ...saga.stateData, ...stateData };
    saga.completedAt = Date.now();
    return saga;
  }

  async get(sagaId)          { return this.sagas.get(sagaId) || null; }
  async getByCorrelation(id) { return [...this.sagas.values()].find(s => s.correlationId === id) || null; }
  async addDeadLetter()      {} // no-op in mock
}

// ─── PostgreSQL Saga Store ────────────────────────────────────────────────────

class PgSagaStore {
  async create(sagaType, correlationId, stateData, timeoutMs = 300_000) {
    const timeoutAt = new Date(Date.now() + timeoutMs);
    const { rows } = await db.query(
      `INSERT INTO saga_instances
         (saga_type, correlation_id, current_step, status, state_data, timeout_at)
       VALUES ($1, $2, 'init', 'running', $3, $4)
       RETURNING id, saga_type AS "sagaType", correlation_id AS "correlationId",
                 current_step AS "currentStep", status, state_data AS "stateData",
                 EXTRACT(EPOCH FROM started_at) * 1000 AS "startedAt"`,
      [sagaType, correlationId, JSON.stringify(stateData), timeoutAt]
    );
    return rows[0];
  }

  async updateStep(sagaId, stepName, status, output = null, error = null) {
    const client = await db.getClient();
    try {
      await client.query('BEGIN');

      // Update saga's current step
      const { rows } = await client.query(
        `UPDATE saga_instances
         SET current_step = $2, updated_at = NOW()
         WHERE id = $1
         RETURNING id, current_step AS "currentStep", status`,
        [sagaId, stepName]
      );

      // Count existing steps to set order
      const { rows: cnt } = await client.query(
        `SELECT COUNT(*)::int AS c FROM saga_step_logs WHERE saga_id = $1`,
        [sagaId]
      );

      // Log the step
      await client.query(
        `INSERT INTO saga_step_logs
           (saga_id, step_name, step_order, action, status, output_data, error_message)
         VALUES ($1, $2, $3, 'execute', $4, $5, $6)`,
        [sagaId, stepName, cnt[0].c + 1, status,
         output ? JSON.stringify(output) : null,
         error  || null]
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

  async complete(sagaId, finalStatus, stateData = {}) {
    const { rows } = await db.query(
      `UPDATE saga_instances
       SET status       = $2,
           state_data   = state_data || $3::jsonb,
           completed_at = NOW()
       WHERE id = $1
       RETURNING id, status`,
      [sagaId, finalStatus, JSON.stringify(stateData)]
    );
    return rows[0];
  }

  async get(sagaId) {
    const { rows } = await db.query(
      `SELECT id, saga_type AS "sagaType", correlation_id AS "correlationId",
              current_step AS "currentStep", status, state_data AS "stateData",
              EXTRACT(EPOCH FROM started_at)   * 1000 AS "startedAt",
              EXTRACT(EPOCH FROM completed_at) * 1000 AS "completedAt"
       FROM saga_instances WHERE id = $1`,
      [sagaId]
    );
    return rows[0] || null;
  }

  async getByCorrelation(correlationId) {
    const { rows } = await db.query(
      `SELECT id, saga_type AS "sagaType", correlation_id AS "correlationId",
              current_step AS "currentStep", status, state_data AS "stateData"
       FROM saga_instances
       WHERE correlation_id = $1
       ORDER BY started_at DESC LIMIT 1`,
      [correlationId]
    );
    return rows[0] || null;
  }

  async addDeadLetter({ topic, eventKey, payload, errorMessage, maxRetries = 5 }) {
    await db.query(
      `INSERT INTO dead_letter_events
         (original_topic, event_key, event_payload, error_message, max_retries, next_retry_at)
       VALUES ($1, $2, $3, $4, $5, NOW() + INTERVAL '5 minutes')`,
      [topic, eventKey || null, JSON.stringify(payload), errorMessage, maxRetries]
    ).catch(err => logger.error('SAGA', `Dead letter insert failed: ${err.message}`));
  }

  async getStats() {
    const { rows } = await db.query(
      `SELECT status, COUNT(*)::int AS cnt
       FROM saga_instances
       WHERE started_at > NOW() - INTERVAL '24 hours'
       GROUP BY status`
    );
    const byStatus = {};
    for (const r of rows) byStatus[r.status] = r.cnt;
    return { last24h: byStatus };
  }
}

// ─── Saga Orchestrator ────────────────────────────────────────────────────────

class SagaService {
  constructor() {
    this.store = USE_PG ? new PgSagaStore() : new InMemorySagaStore();
  }

  // ─── Ride Lifecycle Saga ──────────────────────────────────────────────────
  //
  // Steps: create_ride → match_driver → accept_ride → start_trip → complete_trip
  // Compensations: cancel_ride → release_driver_lock → refund_if_charged

  async startRideLifecycleSaga(rideId, riderId, fareEstimate) {
    const saga = await this.store.create(
      'ride_lifecycle',
      rideId,
      { rideId, riderId, fareEstimate, compensations: [] },
      45 * 60 * 1000 // 45 minute timeout
    );

    logger.info('SAGA', `Ride lifecycle saga started: ${saga.id} (ride: ${rideId})`);
    eventBus.publish('saga_started', { sagaId: saga.id, sagaType: 'ride_lifecycle', rideId });

    return saga;
  }

  async advanceRideStep(sagaId, stepName, output) {
    const saga = await this.store.updateStep(sagaId, stepName, 'completed', output);
    logger.info('SAGA', `Saga ${sagaId} → step [${stepName}] completed`);
    return saga;
  }

  async failRideStep(sagaId, stepName, errorMessage) {
    await this.store.updateStep(sagaId, stepName, 'failed', null, errorMessage);
    await this.store.complete(sagaId, 'compensating');

    logger.warn('SAGA', `Saga ${sagaId} → step [${stepName}] failed: ${errorMessage}`);
    eventBus.publish('saga_compensating', { sagaId, failedStep: stepName, errorMessage });
  }

  async completeSaga(sagaId, finalState = {}) {
    const result = await this.store.complete(sagaId, 'completed', finalState);
    logger.info('SAGA', `Saga ${sagaId} completed`);
    eventBus.publish('saga_completed', { sagaId });
    return result;
  }

  async failSaga(sagaId, reason) {
    const result = await this.store.complete(sagaId, 'failed', { failReason: reason });
    logger.error('SAGA', `Saga ${sagaId} failed: ${reason}`);
    eventBus.publish('saga_failed', { sagaId, reason });
    return result;
  }

  // ─── Payment Saga ─────────────────────────────────────────────────────────
  //
  // Steps: authorize_payment → charge_rider → credit_driver → issue_receipt
  // Compensations: void_authorization → refund_rider

  async startPaymentSaga(rideId, riderId, driverId, amount) {
    const saga = await this.store.create(
      'payment_flow',
      rideId,
      { rideId, riderId, driverId, amount, compensations: [] },
      5 * 60 * 1000 // 5 minute timeout
    );

    logger.info('SAGA', `Payment saga started: ${saga.id} (ride: ${rideId}, ₹${amount})`);
    return saga;
  }

  // ─── Refund Saga ──────────────────────────────────────────────────────────

  async startRefundSaga(rideId, riderId, amount, reason) {
    const saga = await this.store.create(
      'refund_flow',
      rideId,
      { rideId, riderId, amount, reason },
      10 * 60 * 1000
    );

    logger.info('SAGA', `Refund saga started: ${saga.id} (₹${amount} for ride ${rideId})`);
    return saga;
  }

  // ─── Dead Letter Queue ────────────────────────────────────────────────────

  async sendToDeadLetter(topic, eventKey, payload, errorMessage) {
    await this.store.addDeadLetter({ topic, eventKey, payload, errorMessage });
    logger.warn('SAGA', `Dead-lettered event [${topic}]: ${errorMessage}`);
  }

  // ─── Lookup ───────────────────────────────────────────────────────────────

  getSaga(sagaId)              { return this.store.get(sagaId); }
  getSagaByRide(rideId)        { return this.store.getByCorrelation(rideId); }
  getStats()                   { return this.store.getStats?.() || { backend: USE_PG ? 'pg' : 'mock' }; }
}

module.exports = new SagaService();
