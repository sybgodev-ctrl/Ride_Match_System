BEGIN;

-- Replace zone_type string with a cleaner boolean is_allowed.
-- true  = allowed zone (whitelist — pickup must be inside at least one)
-- false = restricted zone (blacklist — pickup blocked if inside)

ALTER TABLE zone_restrictions
  ADD COLUMN IF NOT EXISTS is_allowed BOOLEAN NOT NULL DEFAULT false;

-- Migrate existing data
UPDATE zone_restrictions SET is_allowed = (zone_type = 'allowed');

-- Drop old column
ALTER TABLE zone_restrictions DROP COLUMN IF EXISTS zone_type;

-- Update index
DROP INDEX IF EXISTS idx_zone_restrictions_enabled;
CREATE INDEX IF NOT EXISTS idx_zone_restrictions_enabled
    ON zone_restrictions(is_enabled, applies_to, is_allowed);

COMMIT;
