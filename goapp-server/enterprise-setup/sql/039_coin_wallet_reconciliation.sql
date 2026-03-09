-- 039_coin_wallet_reconciliation.sql
-- Backfill mirror field rider_wallets.coin_balance from authoritative coin_wallets.balance

BEGIN;

-- Ensure missing rider wallets are created before reconciliation.
INSERT INTO rider_wallets (rider_id, coin_balance, cash_balance)
SELECT r.id, COALESCE(cw.balance, 0), 0
FROM riders r
LEFT JOIN coin_wallets cw ON cw.user_id = r.user_id
LEFT JOIN rider_wallets rw ON rw.rider_id = r.id
WHERE rw.rider_id IS NULL;

-- Reconcile mirror values from authoritative coin_wallets.
UPDATE rider_wallets rw
SET coin_balance = cw.balance,
    updated_at = NOW()
FROM riders r
JOIN coin_wallets cw ON cw.user_id = r.user_id
WHERE rw.rider_id = r.id
  AND rw.coin_balance IS DISTINCT FROM cw.balance;

COMMIT;
