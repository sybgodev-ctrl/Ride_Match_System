-- ============================================================
-- GoApp Enterprise Schema: 035 - Vehicle Service Pricing
-- Adds pricing columns to vehicle_types and seeds defaults
-- ============================================================

ALTER TABLE vehicle_types ADD COLUMN IF NOT EXISTS base_fare       NUMERIC(10,2) NOT NULL DEFAULT 25;
ALTER TABLE vehicle_types ADD COLUMN IF NOT EXISTS per_km_rate     NUMERIC(10,2) NOT NULL DEFAULT 8;
ALTER TABLE vehicle_types ADD COLUMN IF NOT EXISTS per_min_rate    NUMERIC(10,2) NOT NULL DEFAULT 1.5;
ALTER TABLE vehicle_types ADD COLUMN IF NOT EXISTS min_fare        NUMERIC(10,2) NOT NULL DEFAULT 50;
ALTER TABLE vehicle_types ADD COLUMN IF NOT EXISTS commission_pct  NUMERIC(5,4)  NOT NULL DEFAULT 0.20;
ALTER TABLE vehicle_types ADD COLUMN IF NOT EXISTS description     TEXT;
ALTER TABLE vehicle_types ADD COLUMN IF NOT EXISTS created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE vehicle_types ADD COLUMN IF NOT EXISTS updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- Seed default vehicle service types with pricing
INSERT INTO vehicle_types
    (name, display_name, category, base_fare, per_km_rate, per_min_rate, min_fare, commission_pct, max_passengers, sort_order, is_active, description)
VALUES
    ('bike',    'Bike',    'bike',    20,  6,  1.0, 40,  0.20, 1, 1, true, 'Quick solo rides'),
    ('auto',    'Auto',    'auto',    25,  8,  1.5, 50,  0.20, 3, 2, true, 'Affordable autos'),
    ('mini',    'Mini',    'economy', 35, 10,  1.5, 60,  0.20, 4, 3, true, 'Budget-friendly cars'),
    ('sedan',   'Sedan',   'comfort', 50, 14,  2.0, 80,  0.20, 4, 4, true, 'Comfortable cars'),
    ('suv',     'SUV',     'xl',      80, 18,  2.5, 120, 0.20, 6, 5, true, 'Spacious rides'),
    ('premium', 'Premium', 'premium', 120, 25, 3.5, 200, 0.18, 4, 6, true, 'Luxury experience')
ON CONFLICT (name) DO UPDATE SET
    display_name   = EXCLUDED.display_name,
    category       = EXCLUDED.category,
    base_fare      = EXCLUDED.base_fare,
    per_km_rate    = EXCLUDED.per_km_rate,
    per_min_rate   = EXCLUDED.per_min_rate,
    min_fare       = EXCLUDED.min_fare,
    commission_pct = EXCLUDED.commission_pct,
    max_passengers = EXCLUDED.max_passengers,
    sort_order     = EXCLUDED.sort_order,
    description    = EXCLUDED.description;

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_vehicle_type_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS vehicle_types_updated_at ON vehicle_types;
CREATE TRIGGER vehicle_types_updated_at
    BEFORE UPDATE ON vehicle_types
    FOR EACH ROW EXECUTE FUNCTION update_vehicle_type_timestamp();
