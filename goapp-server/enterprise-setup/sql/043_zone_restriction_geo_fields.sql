BEGIN;

ALTER TABLE zone_restrictions
  ADD COLUMN IF NOT EXISTS country VARCHAR(80),
  ADD COLUMN IF NOT EXISTS state   VARCHAR(120),
  ADD COLUMN IF NOT EXISTS pincode VARCHAR(20);

CREATE INDEX IF NOT EXISTS idx_zone_restrictions_enabled_geo
  ON zone_restrictions(is_enabled, applies_to, country, state, pincode);

COMMIT;

