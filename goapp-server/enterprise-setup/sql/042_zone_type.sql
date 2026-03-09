BEGIN;

-- NOTE: zone_type was superseded by is_allowed (boolean) in migration 043.
-- This migration is kept for history only. Migration 043 removes zone_type and adds is_allowed.
ALTER TABLE zone_restrictions
  ADD COLUMN IF NOT EXISTS zone_type VARCHAR(10) NOT NULL DEFAULT 'restricted'
  CHECK (zone_type IN ('restricted', 'allowed'));

COMMIT;
