// IP-based rate limit: max 10 OTP requests per IP per 10 minutes.
// Guards against distributing attacks across many phone numbers from one IP.
const IP_RATE_WINDOW_MS = 10 * 60 * 1000;
const IP_RATE_MAX = 10;
const ipRateMap = new Map();

function checkIpRateLimit(ip) {
  const key = ip || 'unknown';
  const now = Date.now();
  const record = ipRateMap.get(key);
  if (record && (now - record.windowStart) < IP_RATE_WINDOW_MS) {
    if (record.count >= IP_RATE_MAX) return false;
    record.count++;
  } else {
    ipRateMap.set(key, { count: 1, windowStart: now });
  }
  return true;
}

const ALLOWED_CHANNELS = new Set(['sms', 'whatsapp', 'voice']);

function registerAuthRoutes(router, ctx) {
  const { repositories } = ctx;
  const OTP_EXPIRES_IN_SEC = 120;

  function normalizePhonePayload(body = {}) {
    const phone = String(body.phone || body.phoneNumber || '').trim();
    const countryCode = String(body.countryCode || '').trim();
    if (!phone) return '';
    if (phone.startsWith('+')) return phone;
    return `${countryCode}${phone}` || phone;
  }

  function mapOtpErrorCode(error = '') {
    const e = String(error).toLowerCase();
    if (e.includes('too many')) return 'OTP_RATE_LIMITED';
    if (e.includes('otp expired')) return 'OTP_EXPIRED';
    if (e.includes('invalid otp') || e.includes('invalid request')) return 'INVALID_OTP';
    return 'AUTH_ERROR';
  }

  function mapOtpErrorMessage(error = '') {
    const e = String(error).toLowerCase();
    if (e.includes('otp expired')) return 'OTP has expired. Please request a new one.';
    if (e.includes('invalid otp')) return 'Invalid OTP. Please check and try again.';
    if (e.includes('invalid request')) return 'Invalid OTP request. Please request a new OTP.';
    return 'Authentication failed. Please try again.';
  }

  function mapUserPayload(user = {}, phone = '') {
    return {
      id: user.userId || user.id || '',
      name: user.name || '',
      phone: (phone || user.phoneNumber || '').replace(/^\+/, ''),
      email: user.email || '',
    };
  }

  const requestOtpHandler = async ({ body, ip }) => {
    if (!checkIpRateLimit(ip)) {
      return {
        status: 429,
        data: { success: false, message: 'Too many requests from this IP', errorCode: 'IP_RATE_LIMITED' },
      };
    }

    const phoneNumber = normalizePhonePayload(body);
    const channel = ALLOWED_CHANNELS.has(body?.channel) ? body.channel : 'sms';
    const result = await repositories.identity.requestOtp({
      phoneNumber,
      channel,
      otpType: 'login',
    });

    if (!result.success) {
      const code = mapOtpErrorCode(result.error);
      return {
        status: code === 'OTP_RATE_LIMITED' ? 429 : 400,
        data: {
          success: false,
          message: result.error || 'Failed to send OTP',
          errorCode: code,
        },
      };
    }

    return {
      status: 200,
      data: {
        success: true,
        message: 'OTP sent successfully',
        data: {
          requestId: result.requestId,
          expiresInSec: OTP_EXPIRES_IN_SEC,
          resendAfterSec: result.resendAfterSec || 30,
        },
      },
    };
  };

  const loginHandler = async ({ body }) => {
    const phoneNumber = normalizePhonePayload(body);
    const result = await repositories.identity.verifyOtp({
      phoneNumber,
      requestId: body?.requestId,
      otpCode: body?.otp,
    });

    if (!result.success) {
      return {
        status: 401,
        data: {
          success: false,
          message: mapOtpErrorMessage(result.error),
          errorCode: mapOtpErrorCode(result.error),
        },
      };
    }

    const pgRepo = require('../repositories/pg/pg-identity-repository');
    const profileComplete = await pgRepo.isProfileComplete(result.user.userId || result.user.id);

    return {
      status: 200,
      data: {
        success: true,
        message: 'Login successful',
        data: {
          accessToken: result.sessionToken,
          isNewUser: result.isNewUser || false,
          profileComplete,
          user: mapUserPayload(result.user, phoneNumber),
        },
      },
    };
  };

  const resendOtpHandler = async ({ body, ip }) => {
    if (!checkIpRateLimit(ip)) {
      return {
        status: 429,
        data: { success: false, message: 'Too many requests from this IP', errorCode: 'IP_RATE_LIMITED' },
      };
    }

    const phoneNumber = normalizePhonePayload(body);
    const result = await repositories.identity.requestOtp({
      phoneNumber,
      channel: 'sms',
      otpType: 'login',
    });

    if (!result.success) {
      const code = mapOtpErrorCode(result.error);
      return {
        status: code === 'OTP_RATE_LIMITED' ? 429 : 400,
        data: {
          success: false,
          message: result.error || 'Failed to resend OTP',
          errorCode: code,
        },
      };
    }

    if (result.resendAfterSec && result.resendAfterSec > 0) {
      return {
        status: 400,
        data: {
          success: false,
          message: 'Resend not allowed yet',
          errorCode: 'RESEND_COOLDOWN_ACTIVE',
          data: { retryAfterSec: result.resendAfterSec },
        },
      };
    }

    return {
      status: 200,
      data: {
        success: true,
        message: 'OTP resent successfully',
        data: {
          requestId: result.requestId,
          expiresInSec: OTP_EXPIRES_IN_SEC,
          resendAfterSec: 30,
        },
      },
    };
  };

  router.register('POST', '/api/v1/auth/request-otp', requestOtpHandler);
  router.register('POST', '/api/v1/auth/login', loginHandler);
  router.register('POST', '/api/v1/auth/resend-otp', resendOtpHandler);

  router.register('POST', '/auth/request-otp', requestOtpHandler);
  router.register('POST', '/auth/login', loginHandler);
  router.register('POST', '/auth/resend-otp', resendOtpHandler);
}

module.exports = registerAuthRoutes;
