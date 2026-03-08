// PostgreSQL-backed Identity Repository
// Tables: users, otp_requests, otp_rate_limits, user_sessions, riders
// Used by identity-service.js when DB_BACKEND=pg

'use strict';

const db     = require('../../services/db');
const crypto = require('crypto');

const OTP_WINDOW_MS = 10 * 60 * 1000; // 10 minutes

class PgIdentityRepository {
  // ─── OTP Rate Limiting ────────────────────────────────────────────────────

  async getRateLimit(phone) {
    const { rows } = await db.query(
      `SELECT request_count, is_blocked, blocked_until
       FROM otp_rate_limits
       WHERE phone_number = $1
         AND window_start > NOW() - INTERVAL '10 minutes'
       ORDER BY window_start DESC LIMIT 1`,
      [phone]
    );
    return rows[0] || null;
  }

  async incrementRateLimit(phone) {
    const windowStart = new Date(
      Math.floor(Date.now() / OTP_WINDOW_MS) * OTP_WINDOW_MS
    );
    const { rows } = await db.query(
      `INSERT INTO otp_rate_limits (phone_number, window_start, request_count)
       VALUES ($1, $2, 1)
       ON CONFLICT (phone_number, window_start)
       DO UPDATE SET request_count = otp_rate_limits.request_count + 1
       RETURNING request_count, is_blocked, blocked_until`,
      [phone, windowStart]
    );
    return rows[0];
  }

  // ─── OTP Requests ─────────────────────────────────────────────────────────

  async expirePendingOtpsByPhone(phoneNumber) {
    await db.query(
      `UPDATE otp_requests
       SET status = 'expired'
       WHERE phone_number = $1
         AND status = 'pending'`,
      [phoneNumber]
    );
  }

  async createOtpRequest({ requestId, phoneNumber, otpCode, otpType, channel, expiresAt }) {
    await db.query(
      `INSERT INTO otp_requests
         (id, phone_number, otp_code, otp_type, channel, status, expires_at)
       VALUES ($1, $2, $3, $4, $5, 'pending', $6)`,
      [requestId, phoneNumber, otpCode, otpType, channel, new Date(expiresAt)]
    );
  }

  async getOtpRequest(requestId) {
    const { rows } = await db.query(
      `SELECT id, phone_number, otp_code, otp_type, status,
              attempts, max_attempts,
              EXTRACT(EPOCH FROM expires_at) * 1000 AS "expiresAt",
              EXTRACT(EPOCH FROM created_at) * 1000 AS "createdAt"
       FROM otp_requests WHERE id = $1`,
      [requestId]
    );
    return rows[0] || null;
  }

  async getActiveOtpByPhone(phone) {
    const { rows } = await db.query(
      `SELECT id, phone_number, otp_code, otp_type, status,
              attempts, max_attempts,
              EXTRACT(EPOCH FROM expires_at) * 1000  AS "expiresAt",
              EXTRACT(EPOCH FROM (created_at + INTERVAL '30 seconds')) * 1000 AS "resendAt"
       FROM otp_requests
       WHERE phone_number = $1
         AND status = 'pending'
         AND expires_at > NOW()
       ORDER BY created_at DESC LIMIT 1`,
      [phone]
    );
    return rows[0] || null;
  }

  // Atomically increment attempts and optionally set a new status
  async recordOtpAttempt(requestId, newStatus) {
    const { rows } = await db.query(
      `UPDATE otp_requests
       SET attempts = attempts + 1,
           status   = COALESCE($2, status),
           verified_at = CASE WHEN $2 = 'verified' THEN NOW() ELSE verified_at END
       WHERE id = $1
       RETURNING attempts, status`,
      [requestId, newStatus || null]
    );
    return rows[0];
  }

  // ─── User Profiles ────────────────────────────────────────────────────────

  async upsertUserProfile({ userId, name, gender, emergencyContact }) {
    await db.query(
      `INSERT INTO user_profiles (user_id, display_name, gender, emergency_contact)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (user_id) DO UPDATE
         SET display_name       = EXCLUDED.display_name,
             gender             = EXCLUDED.gender,
             emergency_contact  = EXCLUDED.emergency_contact,
             updated_at         = NOW()`,
      [userId, name, gender, emergencyContact || null]
    );
  }

  async getUserProfile(userId) {
    const { rows } = await db.query(
      `SELECT display_name AS name, gender, emergency_contact
       FROM user_profiles WHERE user_id = $1`,
      [userId]
    );
    return rows[0] || null;
  }

  async updateUserEmail(userId, email) {
    await db.query(
      `UPDATE users SET email = $2, updated_at = NOW() WHERE id = $1`,
      [userId, email]
    );
  }

  async isProfileComplete(userId) {
    const { rows } = await db.query(
      `SELECT 1 FROM user_profiles
       WHERE user_id = $1
         AND display_name IS NOT NULL AND display_name <> ''
         AND gender       IS NOT NULL AND gender       <> ''`,
      [userId]
    );
    return rows.length > 0;
  }

  // ─── Users ────────────────────────────────────────────────────────────────

  // Upserts the user row and also ensures a riders record exists (for rider type)
  async upsertUser({ userId, phoneNumber, userType }) {
    const client = await db.getClient();
    try {
      await client.query('BEGIN');

      const { rows } = await client.query(
        `INSERT INTO users (id, phone_number, user_type, phone_verified, status)
         VALUES ($1, $2, $3, true, 'active')
         ON CONFLICT (phone_number)
         DO UPDATE SET phone_verified = true, updated_at = NOW()
         RETURNING id, phone_number, user_type, status, phone_verified,
                   EXTRACT(EPOCH FROM created_at) * 1000 AS "createdAt"`,
        [userId, phoneNumber, userType]
      );
      const user = rows[0];

      // Ensure a riders row exists so wallet / ride FKs resolve
      if (user.user_type === 'rider') {
        await client.query(
          `INSERT INTO riders (user_id) VALUES ($1)
           ON CONFLICT (user_id) DO NOTHING`,
          [user.id]
        );
      }

      await client.query('COMMIT');
      return user;
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  async getUserByPhone(phone) {
    const { rows } = await db.query(
      `SELECT id, phone_number, user_type, status, phone_verified,
              EXTRACT(EPOCH FROM created_at) * 1000 AS "createdAt"
       FROM users WHERE phone_number = $1 AND deleted_at IS NULL`,
      [phone]
    );
    return rows[0] || null;
  }

  async getUserById(userId) {
    const { rows } = await db.query(
      `SELECT id, phone_number, user_type, status, phone_verified,
              EXTRACT(EPOCH FROM created_at) * 1000 AS "createdAt"
       FROM users WHERE id = $1 AND deleted_at IS NULL`,
      [userId]
    );
    return rows[0] || null;
  }

  async getUsers(limit = 100) {
    const { rows } = await db.query(
      `SELECT id, phone_number, user_type, status, phone_verified,
              EXTRACT(EPOCH FROM created_at) * 1000 AS "createdAt"
       FROM users WHERE deleted_at IS NULL
       ORDER BY created_at DESC LIMIT $1`,
      [limit]
    );
    return rows;
  }

  // ─── Sessions ─────────────────────────────────────────────────────────────

  async createSession({ sessionToken, userId, expiresAt }) {
    await db.query(
      `INSERT INTO user_sessions (user_id, session_token, is_active, expires_at)
       VALUES ($1, $2, true, $3)
       ON CONFLICT (session_token) DO NOTHING`,
      [userId, sessionToken, new Date(expiresAt)]
    );
  }

  async getSession(sessionToken) {
    const { rows } = await db.query(
      `SELECT session_token, user_id,
              EXTRACT(EPOCH FROM expires_at) * 1000 AS "expiresAt",
              EXTRACT(EPOCH FROM created_at) * 1000 AS "createdAt"
       FROM user_sessions
       WHERE session_token = $1
         AND is_active = true
         AND expires_at > NOW()`,
      [sessionToken]
    );
    return rows[0] || null;
  }

  async revokeSession(sessionToken) {
    await db.query(
      `UPDATE user_sessions
       SET is_active = false, revoked_at = NOW()
       WHERE session_token = $1`,
      [sessionToken]
    );
  }

  // ─── Stats ────────────────────────────────────────────────────────────────

  async getStats() {
    const [{ rows: u }, { rows: s }, { rows: o }] = await Promise.all([
      db.query(`SELECT COUNT(*)::int AS cnt FROM users WHERE deleted_at IS NULL`),
      db.query(`SELECT COUNT(*)::int AS cnt FROM user_sessions WHERE is_active = true AND expires_at > NOW()`),
      db.query(
        `SELECT status, COUNT(*)::int AS cnt
         FROM otp_requests
         WHERE created_at > NOW() - INTERVAL '24 hours'
         GROUP BY status`
      ),
    ]);
    const oByStatus = {};
    for (const row of o) oByStatus[row.status] = row.cnt;
    return {
      users:    u[0].cnt,
      sessions: s[0].cnt,
      otp: {
        pending:  oByStatus.pending  || 0,
        verified: oByStatus.verified || 0,
        failed:   oByStatus.failed   || 0,
        expired:  oByStatus.expired  || 0,
        total:    Object.values(oByStatus).reduce((a, b) => a + b, 0),
      },
    };
  }
}

module.exports = new PgIdentityRepository();
