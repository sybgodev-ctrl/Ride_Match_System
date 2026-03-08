// PostgreSQL-backed Rider Wallet Repository
// Tables: rider_wallets, wallet_transactions
// Used by wallet-service.js when DB_BACKEND=pg

'use strict';

const db = require('../../services/db');

class PgWalletRepository {
  // ─── Ensure wallet row exists ─────────────────────────────────────────────

  async _ensureWallet(userId) {
    await db.query(
      `INSERT INTO rider_wallets (rider_id)
       SELECT id FROM riders WHERE user_id = $1
       ON CONFLICT (rider_id) DO NOTHING`,
      [userId]
    );
  }

  // ─── Balance ──────────────────────────────────────────────────────────────

  async getBalance(userId) {
    await this._ensureWallet(userId);
    const { rows } = await db.query(
      `SELECT rw.coin_balance, rw.cash_balance
       FROM rider_wallets rw
       JOIN riders r ON r.id = rw.rider_id
       WHERE r.user_id = $1`,
      [userId]
    );
    return rows[0] || { coin_balance: 0, cash_balance: 0 };
  }

  // ─── Atomic balance adjustment + transaction log ──────────────────────────

  async adjustAndRecord(userId, { coinDelta = 0, cashDelta = 0 }, tx) {
    const client = await db.getClient();
    try {
      await client.query('BEGIN');

      const { rows } = await client.query(
        `UPDATE rider_wallets SET
           coin_balance = GREATEST(0, coin_balance + $2),
           cash_balance = GREATEST(0, cash_balance + $3),
           updated_at   = NOW()
         WHERE rider_id = (SELECT id FROM riders WHERE user_id = $1)
         RETURNING coin_balance, cash_balance`,
        [userId, coinDelta, cashDelta]
      );

      if (!rows.length) throw new Error(`Wallet not found for user ${userId}`);
      const { coin_balance, cash_balance } = rows[0];

      // Record transaction
      await client.query(
        `INSERT INTO wallet_transactions
           (rider_id, transaction_type, amount, coins, reference_id, metadata)
         VALUES (
           (SELECT id FROM riders WHERE user_id = $1),
           $2, $3, $4, $5, $6
         )`,
        [
          userId,
          tx.type,
          Math.abs(cashDelta) || 0,
          Math.abs(coinDelta) || 0,
          tx.rideId || null,
          JSON.stringify(tx),
        ]
      );

      await client.query('COMMIT');
      return { coinBalance: coin_balance, cashBalance: cash_balance };
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  // ─── Transaction history ──────────────────────────────────────────────────

  async getTransactions(userId, limit = 20) {
    const { rows } = await db.query(
      `SELECT wt.transaction_type AS type, wt.amount, wt.coins,
              wt.reference_id AS "rideId", wt.metadata,
              EXTRACT(EPOCH FROM wt.created_at) * 1000 AS "createdAt"
       FROM wallet_transactions wt
       JOIN riders r ON r.id = wt.rider_id
       WHERE r.user_id = $1
       ORDER BY wt.created_at DESC LIMIT $2`,
      [userId, limit]
    );
    return rows;
  }

  // ─── Stats ────────────────────────────────────────────────────────────────

  async getStats() {
    const { rows } = await db.query(
      `SELECT COUNT(*)::int          AS "totalUsers",
              SUM(coin_balance)::int AS "totalCoinsInCirculation",
              SUM(cash_balance)      AS "totalCashInWallets"
       FROM rider_wallets`
    );
    const r = rows[0];
    return {
      totalUsers:                r.totalUsers || 0,
      totalCoinsInCirculation:   r.totalCoinsInCirculation || 0,
      totalCashInWallets:        parseFloat(r.totalCashInWallets || 0).toFixed(2),
    };
  }
}

module.exports = new PgWalletRepository();
