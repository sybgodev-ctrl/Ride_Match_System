// GoApp Identity Service
// OTP-only auth flow.
//
// DB_BACKEND=mock  → all state in in-memory Maps (zero setup)
// DB_BACKEND=pg    → all state persisted to PostgreSQL via pg-identity-repository

'use strict';

const crypto = require('crypto');
const config = require('../config');
const { logger, eventBus } = require('../utils/logger');

const USE_PG = config.db.backend === 'pg';
const pgRepo = USE_PG ? require('../repositories/pg/pg-identity-repository') : null;

// OTP rate limit constants (used in both modes)
const OTP_RATE_WINDOW_MS = 10 * 60 * 1000;
const OTP_RATE_MAX       = 5;

class IdentityService {
  constructor() {
    // ── In-memory stores (mock mode only) ──
    this.usersByPhone    = new Map();
    this.usersById       = new Map();
    this.otpByRequestId  = new Map();
    this.otpIndexByPhone = new Map();
    this.sessions        = new Map();
    this.otpRateByPhone  = new Map();
    this.seedMeta        = null;
  }

  // ─── Seed (mock mode only) ────────────────────────────────────────────────

  seedUsers(users = []) {
    if (USE_PG) {
      logger.warn('IDENTITY', 'seedUsers() is a no-op in pg mode — users are created via OTP verify');
      return { seededAt: Date.now(), count: 0 };
    }

    this.usersByPhone.clear();
    this.usersById.clear();

    for (const user of users) {
      const phone = this._normalizePhone(user.phoneNumber);
      const row = {
        userId:        user.userId,
        phoneNumber:   phone,
        name:          user.name,
        userType:      user.userType || 'rider',
        phoneVerified: Boolean(user.phoneVerified),
        status:        user.status || 'active',
        createdAt:     user.createdAt || Date.now(),
      };
      this.usersByPhone.set(phone, row);
      this.usersById.set(row.userId, row);
    }

    this.seedMeta = { seededAt: Date.now(), count: this.usersById.size };
    return this.seedMeta;
  }

  // ─── Request OTP ──────────────────────────────────────────────────────────

  async requestOtp({ phoneNumber, otpType = 'login', channel = 'sms' }) {
    const phone = this._normalizePhone(phoneNumber);
    if (!phone || phone.replace(/\D/g, '').length < 7) {
      return { success: false, error: 'valid phoneNumber required' };
    }

    const now = Date.now();

    // ── Rate Limiting ──
    if (USE_PG) {
      const rateRecord = await pgRepo.getRateLimit(phone);
      if (rateRecord && rateRecord.request_count >= OTP_RATE_MAX) {
        logger.warn('IDENTITY', `OTP rate limit hit (pg) for ${phone}`);
        return { success: false, error: 'Too many OTP requests. Try again later.', retryAfterSec: 60 };
      }
      await pgRepo.incrementRateLimit(phone);
    } else {
      const rateRecord = this.otpRateByPhone.get(phone);
      if (rateRecord && (now - rateRecord.windowStart) < OTP_RATE_WINDOW_MS) {
        if (rateRecord.count >= OTP_RATE_MAX) {
          const retryAfterSec = Math.ceil((rateRecord.windowStart + OTP_RATE_WINDOW_MS - now) / 1000);
          logger.warn('IDENTITY', `OTP rate limit hit for ${phone}`);
          return { success: false, error: 'Too many OTP requests. Try again later.', retryAfterSec };
        }
        rateRecord.count++;
      } else {
        this.otpRateByPhone.set(phone, { count: 1, windowStart: now });
      }
    }

    // ── Reuse active OTP if within resend cooldown ──
    if (USE_PG) {
      const existing = await pgRepo.getActiveOtpByPhone(phone);
      if (existing && existing.expiresAt > now && existing.resendAt > now) {
        return {
          success: true,
          requestId: existing.id,
          expiresAt: existing.expiresAt,
          resendAfterSec: Math.ceil((existing.resendAt - now) / 1000),
        };
      }
    } else {
      const existingId = this.otpIndexByPhone.get(phone);
      if (existingId) {
        const existing = this.otpByRequestId.get(existingId);
        if (existing && existing.status === 'pending' && existing.expiresAt > now && existing.resendAt > now) {
          return {
            success: true,
            requestId: existing.requestId,
            expiresAt: existing.expiresAt,
            resendAfterSec: Math.ceil((existing.resendAt - now) / 1000),
          };
        }
      }
    }

    // ── Generate new OTP ──
    const otpCode   = this._generateOtp();
    const requestId = `OTP-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    const expiresAt = now + 120_000;
    const resendAt  = now +  30_000;

    if (USE_PG) {
      await pgRepo.createOtpRequest({ requestId, phoneNumber: phone, otpCode, otpType, channel, expiresAt });
    } else {
      const request = {
        requestId, phoneNumber: phone, otpCode, otpType, channel,
        status: 'pending', attempts: 0, maxAttempts: 3,
        createdAt: now, resendAt, expiresAt, verifiedAt: null,
      };
      this.otpByRequestId.set(requestId, request);
      this.otpIndexByPhone.set(phone, requestId);
    }

    eventBus.publish('otp_requested', { phoneNumber: phone, requestId, otpType, channel });
    logger.info('IDENTITY', `OTP generated for ${phone} (${requestId})`);

    // Deliver OTP via SMS
    try {
      const smsService = require('./sms-service');
      Promise.resolve(smsService.sendOtp(phone, otpCode, requestId))
        .catch(err => logger.warn('IDENTITY', `SMS delivery failed: ${err.message}`));
    } catch (e) {
      logger.warn('IDENTITY', `SMS delivery skipped: ${e.message}`);
    }

    return { success: true, requestId, expiresAt };
  }

  // ─── Verify OTP ───────────────────────────────────────────────────────────

  async verifyOtp({ phoneNumber, requestId, otpCode }) {
    const phone = this._normalizePhone(phoneNumber);
    const now   = Date.now();

    if (USE_PG) {
      const request = await pgRepo.getOtpRequest(requestId);
      if (!request || request.phone_number !== phone) {
        return { success: false, error: 'invalid request' };
      }
      if (request.status !== 'pending') {
        return { success: false, error: `otp status is ${request.status}` };
      }
      if (now > request.expiresAt) {
        await pgRepo.recordOtpAttempt(requestId, 'expired');
        return { success: false, error: 'otp expired' };
      }
      if (request.otp_code !== String(otpCode || '')) {
        const newStatus = (request.attempts + 1) >= request.max_attempts ? 'failed' : null;
        const updated   = await pgRepo.recordOtpAttempt(requestId, newStatus);
        return { success: false, error: 'invalid otp', attempts: updated.attempts };
      }

      // Correct OTP — mark verified, upsert user + session
      await pgRepo.recordOtpAttempt(requestId, 'verified');
      const userId = crypto.randomUUID();
      const user   = await pgRepo.upsertUser({ userId, phoneNumber: phone, userType: 'rider' });

      const sessionToken    = crypto.randomUUID();
      const sessionExpiresAt = now + 24 * 3600 * 1000;
      await pgRepo.createSession({ sessionToken, userId: user.id, expiresAt: sessionExpiresAt });
      this.sessions.set(sessionToken, {
        sessionToken,
        userId: user.id,
        phoneNumber: phone,
        createdAt: now,
        expiresAt: sessionExpiresAt,
      });

      eventBus.publish('otp_verified', { requestId, userId: user.id, phoneNumber: phone });

      return {
        success: true,
        user: {
          userId:        user.id,
          phoneNumber:   user.phone_number,
          userType:      user.user_type,
          phoneVerified: user.phone_verified,
          status:        user.status,
          createdAt:     user.createdAt,
        },
        sessionToken,
      };
    }

    // ── Mock mode ──
    const request = this.otpByRequestId.get(requestId);
    if (!request || request.phoneNumber !== phone) {
      return { success: false, error: 'invalid request' };
    }
    if (request.status !== 'pending') {
      return { success: false, error: `otp status is ${request.status}` };
    }
    if (now > request.expiresAt) {
      request.status = 'expired';
      return { success: false, error: 'otp expired' };
    }

    request.attempts++;
    if (request.otpCode !== String(otpCode || '')) {
      if (request.attempts >= request.maxAttempts) request.status = 'failed';
      return { success: false, error: 'invalid otp', attempts: request.attempts };
    }

    request.status     = 'verified';
    request.verifiedAt = now;

    let user = this.usersByPhone.get(phone);
    if (!user) {
      user = {
        userId:        `USR-${crypto.randomUUID().slice(0, 8).toUpperCase()}`,
        phoneNumber:   phone,
        name:          `User-${this.usersById.size + 1}`,
        userType:      'rider',
        phoneVerified: true,
        status:        'active',
        createdAt:     now,
      };
      this.usersByPhone.set(phone, user);
      this.usersById.set(user.userId, user);
    } else {
      user.phoneVerified = true;
    }

    const sessionToken = crypto.randomUUID();
    this.sessions.set(sessionToken, {
      sessionToken,
      userId:      user.userId,
      phoneNumber: phone,
      createdAt:   now,
      expiresAt:   now + 24 * 3600 * 1000,
    });

    eventBus.publish('otp_verified', { requestId, userId: user.userId, phoneNumber: phone });
    return { success: true, user, sessionToken };
  }

  // ─── Validate Session ─────────────────────────────────────────────────────

  async validateSession(sessionToken) {
    if (!sessionToken) return null;
    if (USE_PG) {
      const pgSession = await pgRepo.getSession(sessionToken);
      if (!pgSession) return null;
      const session = {
        sessionToken: pgSession.session_token,
        userId: pgSession.user_id,
        createdAt: pgSession.createdAt,
        expiresAt: pgSession.expiresAt,
      };
      this.sessions.set(sessionToken, session);
      return session;
    }

    const session = this.sessions.get(sessionToken);
    if (!session) return null;
    if (Date.now() > session.expiresAt) {
      this.sessions.delete(sessionToken);
      return null;
    }
    return session;
  }

  // ─── Read Methods ─────────────────────────────────────────────────────────

  async getUsers(limit = 100) {
    if (USE_PG) return pgRepo.getUsers(limit);
    return [...this.usersById.values()].slice(0, limit);
  }

  async getStats() {
    if (USE_PG) return pgRepo.getStats();

    const otpRows = [...this.otpByRequestId.values()];
    return {
      users:    this.usersById.size,
      sessions: this.sessions.size,
      otp: {
        total:    otpRows.length,
        pending:  otpRows.filter(r => r.status === 'pending').length,
        verified: otpRows.filter(r => r.status === 'verified').length,
        failed:   otpRows.filter(r => r.status === 'failed').length,
        expired:  otpRows.filter(r => r.status === 'expired').length,
      },
      seedMeta: this.seedMeta,
    };
  }

  // ─── Private Helpers ──────────────────────────────────────────────────────

  _normalizePhone(phoneNumber) {
    if (!phoneNumber) return '';
    return String(phoneNumber).replace(/[^\d+]/g, '');
  }

  _generateOtp() {
    return String(crypto.randomInt(100000, 999999));
  }
}

module.exports = new IdentityService();
