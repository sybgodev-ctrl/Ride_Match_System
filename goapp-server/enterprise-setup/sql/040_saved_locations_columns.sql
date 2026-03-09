-- 040_saved_locations_columns.sql
-- Adds usage_count, last_used_at, updated_at columns to rider_saved_places.
-- Idempotent: safe to run multiple times; each block checks information_schema
-- before altering the table so re-runs on an already-migrated DB are no-ops.

BEGIN;

-- usage_count: number of times the rider has selected this saved location
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'rider_saved_places' AND column_name = 'usage_count'
  ) THEN
    ALTER TABLE rider_saved_places
      ADD COLUMN usage_count INTEGER NOT NULL DEFAULT 0;
  END IF;
END $$;

-- last_used_at: timestamp of the most recent selection; used as secondary sort key
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'rider_saved_places' AND column_name = 'last_used_at'
  ) THEN
    ALTER TABLE rider_saved_places
      ADD COLUMN last_used_at TIMESTAMPTZ;
  END IF;
END $$;

-- updated_at: standard audit column; set to NOW() on every UPDATE
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'rider_saved_places' AND column_name = 'updated_at'
  ) THEN
    ALTER TABLE rider_saved_places
      ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
  END IF;
END $$;

-- Composite index for the default list sort: most-used first, most-recently-used second
CREATE INDEX IF NOT EXISTS idx_rider_saved_usage
  ON rider_saved_places(rider_id, usage_count DESC, last_used_at DESC NULLS LAST);

COMMIT;
