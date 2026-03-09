-- 036_schema_alignment_runtime_fallback_removal.sql
-- One-time schema alignment for mixed/partially-migrated environments.
-- Safe to run multiple times (idempotent).

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- Riders: columns required by welcome bonus + referral code flows
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE riders
  ADD COLUMN IF NOT EXISTS welcome_bonus_claimed BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE riders
  ADD COLUMN IF NOT EXISTS referral_code VARCHAR(20);

-- Defensive backfill in case older schema had nullable values
UPDATE riders
SET welcome_bonus_claimed = false
WHERE welcome_bonus_claimed IS NULL;

-- If duplicate referral codes exist, keep one row and clear the rest before
-- creating a partial unique index.
WITH ranked AS (
  SELECT id,
         referral_code,
         ROW_NUMBER() OVER (
           PARTITION BY referral_code
           ORDER BY created_at ASC, id ASC
         ) AS rn
  FROM riders
  WHERE referral_code IS NOT NULL
)
UPDATE riders r
SET referral_code = NULL
FROM ranked d
WHERE r.id = d.id
  AND d.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS idx_riders_referral_code_unique
  ON riders (referral_code)
  WHERE referral_code IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- Emergency contacts: soft-delete support expected by safety repository
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE emergency_contacts
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_emergency_contacts_active
  ON emergency_contacts (user_id)
  WHERE deleted_at IS NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- Push tokens: unique token required for conflict-safe upsert semantics
-- ─────────────────────────────────────────────────────────────────────────────
DELETE FROM push_tokens a
USING push_tokens b
WHERE a.ctid < b.ctid
  AND a.token = b.token;

CREATE UNIQUE INDEX IF NOT EXISTS idx_push_tokens_token_unique
  ON push_tokens(token);

COMMIT;
