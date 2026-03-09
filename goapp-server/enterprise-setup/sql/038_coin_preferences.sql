-- 038_coin_preferences.sql
-- Persist rider coin auto-use preference and keep backend-authoritative policy source.

BEGIN;

CREATE TABLE IF NOT EXISTS user_coin_preferences (
  user_id            UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  auto_use_enabled   BOOLEAN NOT NULL DEFAULT false,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_coin_preferences_auto_use
  ON user_coin_preferences (auto_use_enabled);

-- Ensure policy keys exist in coin_config even on partially migrated environments.
INSERT INTO coin_config (config_key, config_value, description)
VALUES
  ('coin_inr_value', '0.10', '1 coin = INR value for redemption'),
  ('coins_per_inr_earn', '10', 'earn 1 coin per N INR fare'),
  ('min_redeem_coins', '10', 'minimum coins needed to redeem'),
  ('max_redeem_pct', '0.20', 'max share of fare redeemable by coins')
ON CONFLICT (config_key) DO NOTHING;

COMMIT;
