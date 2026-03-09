-- 050_zone_restrictions_enforce_both.sql
-- Permanently enforce applies_to='both' for zone_restrictions.

BEGIN;

-- Backfill safety (idempotent).
UPDATE zone_restrictions
SET applies_to = 'both',
    updated_at = NOW()
WHERE applies_to IS DISTINCT FROM 'both';

-- Add a strict constraint so non-both cannot persist.
ALTER TABLE zone_restrictions
  DROP CONSTRAINT IF EXISTS chk_zone_restrictions_applies_to_both;

ALTER TABLE zone_restrictions
  ADD CONSTRAINT chk_zone_restrictions_applies_to_both
  CHECK (applies_to = 'both');

-- Trigger guard (insert/update): coerce to 'both' before row write.
CREATE OR REPLACE FUNCTION enforce_zone_restrictions_applies_to_both()
RETURNS trigger AS $$
BEGIN
  NEW.applies_to := 'both';
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_zone_restrictions_applies_to_both ON zone_restrictions;

CREATE TRIGGER trg_zone_restrictions_applies_to_both
BEFORE INSERT OR UPDATE ON zone_restrictions
FOR EACH ROW
EXECUTE FUNCTION enforce_zone_restrictions_applies_to_both();

COMMIT;

