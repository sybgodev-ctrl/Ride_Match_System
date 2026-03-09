// GoApp Database Interface — PostgreSQL only
//
// Exported API:
//   query(text, params)  → Promise<{ rows, rowCount }>
//   getClient()          → Promise<pg.PoolClient>
//   pool                 → pg.Pool

'use strict';

const config = require('../config');
const { logger } = require('../utils/logger');

const { Pool } = require('pg');

const pool = new Pool({
  host:     config.db.host,
  port:     config.db.port,
  user:     config.db.user,
  password: config.db.password,
  database: config.db.database,
  min:      config.db.pool.min,
  max:      config.db.pool.max,
  // Idle connections released after 30s to avoid holding resources
  idleTimeoutMillis: 30_000,
  // Fail fast if Postgres is unreachable — reveals misconfiguration at startup
  connectionTimeoutMillis: 5_000,
  ...(config.db.ssl ? { ssl: { rejectUnauthorized: true } } : {}),
});

pool.on('error', (err) => {
  logger.error('DB', `PG pool error: ${err.message}`);
});

pool.on('connect', () => {
  logger.info('DB', `Connected to PostgreSQL ${config.db.host}:${config.db.port}/${config.db.database}`);
});

logger.info('DB', `Using PostgreSQL adapter — pool min:${config.db.pool.min} max:${config.db.pool.max}`);

async function query(text, params) {
  const t0 = Date.now();
  try {
    const result = await pool.query(text, params);
    const duration = Date.now() - t0;
    if (duration > 1000) {
      logger.warn('DB', `Slow query (${duration}ms): ${String(text).slice(0, 120)}`);
    }
    return result;
  } catch (err) {
    logger.error('DB', `Query error: ${err.message} | SQL: ${String(text).slice(0, 120)}`);
    throw err;
  }
}

async function getClient() {
  return pool.connect();
}

module.exports = {
  query,
  getClient,
  pool,
  backend: 'pg',
};
