const config = require('./index');

function validateConfig({ strict = false } = {}) {
  const errors = [];
  const warnings = [];
  const nodeEnv = process.env.NODE_ENV || 'development';
  const isDevelopment = nodeEnv === 'development';

  if (!config.admin.token || config.admin.token === 'goapp-admin-secret') {
    const msg = 'GOAPP_ADMIN_TOKEN is using default value.';
    if (!isDevelopment || strict) errors.push(msg); else warnings.push(msg);
  }

  if (!config.otp?.secret || config.otp.secret === 'dev-otp-secret-change-me-in-prod') {
    const msg = 'OTP_SECRET is using the default dev value. Set a strong random secret for production.';
    if (!isDevelopment || strict) errors.push(msg); else warnings.push(msg);
  }

  if ((!isDevelopment || strict) && (!config.security.corsOrigin || config.security.corsOrigin === '*')) {
    errors.push('CORS_ORIGIN must be explicitly set outside development.');
  }

  if ((!isDevelopment || strict) && config.sms.provider !== 'console') {
    if (config.sms.provider === 'twilio') {
      if (!config.sms.twilio.accountSid || !config.sms.twilio.authToken || !config.sms.twilio.fromNumber) {
        errors.push('Twilio SMS provider selected but credentials are incomplete.');
      }
    }
  }

  // ─── Database validation ────────────────────────────────────────────────────
  const needsRealServices = !isDevelopment;

  if (needsRealServices && config.db.backend !== 'pg') {
    errors.push(`DB_BACKEND must be 'pg' in ${nodeEnv} environment (got '${config.db.backend}').`);
  }

  if (config.db.backend === 'pg') {
    if (!config.db.password) errors.push('POSTGRES_PASSWORD is required when DB_BACKEND=pg.');
    if (!config.db.database) errors.push('POSTGRES_DB is required when DB_BACKEND=pg.');
    if (config.db.pool.max < config.db.pool.min) {
      errors.push(`POSTGRES_POOL_MAX (${config.db.pool.max}) must be >= POSTGRES_POOL_MIN (${config.db.pool.min}).`);
    }
    if (!isDevelopment && !config.db.ssl) {
      warnings.push('POSTGRES_SSL is not enabled in non-development environments. Consider enabling SSL for managed databases.');
    }
  }

  // ─── Redis validation ───────────────────────────────────────────────────────

  if (needsRealServices && config.redis.backend !== 'real') {
    errors.push(`REDIS_BACKEND must be 'real' in ${nodeEnv} environment (got '${config.redis.backend}').`);
  }

  if (config.redis.backend === 'real' && !config.redis.host) {
    errors.push('REDIS_HOST is required when REDIS_BACKEND=real.');
  }

  return { ok: errors.length === 0, errors, warnings, profile: nodeEnv };
}

module.exports = validateConfig;
