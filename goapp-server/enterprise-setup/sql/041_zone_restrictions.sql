-- 041_zone_restrictions.sql
-- Persistent, admin-managed zone restrictions (circular zones, no PostGIS required).
-- Supports per-role applicability (rider / driver / both) and enable/disable toggle.
-- Idempotent: safe to run multiple times.

BEGIN;

CREATE TABLE IF NOT EXISTS zone_restrictions (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name                 VARCHAR(200) NOT NULL,
    lat                  DECIMAL(10,7) NOT NULL,
    lng                  DECIMAL(10,7) NOT NULL,
    radius_km            DECIMAL(8,3)  NOT NULL CHECK (radius_km > 0),
    applies_to           VARCHAR(10)   NOT NULL DEFAULT 'both'
                         CHECK (applies_to IN ('rider', 'driver', 'both')),
    is_enabled           BOOLEAN       NOT NULL DEFAULT true,
    restriction_message  TEXT          NOT NULL
                         DEFAULT 'Service is not available in this area.',
    created_by           VARCHAR(100),
    created_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- Partial index — only rows queried at runtime (enabled zones) are indexed
CREATE INDEX IF NOT EXISTS idx_zone_restrictions_enabled
    ON zone_restrictions(is_enabled, applies_to);

COMMIT;
