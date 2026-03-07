-- ============================================================
-- GoApp Enterprise Schema: 007 - Pricing Service
-- Domain: Pricing Service (14 tables)
-- ============================================================

CREATE TABLE IF NOT EXISTS pricing_rules (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    city_region_id      UUID REFERENCES city_regions(id),
    vehicle_type_id     UUID REFERENCES vehicle_types(id),
    ride_type           VARCHAR(30),
    rule_name           VARCHAR(100) NOT NULL,
    rule_type           VARCHAR(30) CHECK (rule_type IN ('base','surge','discount','cap','minimum','special')),
    conditions          JSONB,
    priority            INTEGER DEFAULT 0,
    is_active           BOOLEAN DEFAULT true,
    effective_from      TIMESTAMPTZ NOT NULL,
    effective_until     TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS base_fares (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    city_region_id      UUID NOT NULL REFERENCES city_regions(id),
    vehicle_type_id     UUID NOT NULL REFERENCES vehicle_types(id),
    base_fare           DECIMAL(10,2) NOT NULL,
    minimum_fare        DECIMAL(10,2) NOT NULL,
    booking_fee         DECIMAL(10,2) DEFAULT 0,
    cancellation_fee    DECIMAL(10,2) DEFAULT 0,
    currency            VARCHAR(3) DEFAULT 'INR',
    effective_from      TIMESTAMPTZ NOT NULL,
    effective_until     TIMESTAMPTZ,
    UNIQUE(city_region_id, vehicle_type_id, effective_from)
);

CREATE TABLE IF NOT EXISTS distance_rates (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    base_fare_id        UUID NOT NULL REFERENCES base_fares(id),
    from_km             DECIMAL(6,2) NOT NULL DEFAULT 0,
    to_km               DECIMAL(6,2),
    rate_per_km         DECIMAL(8,2) NOT NULL
);

CREATE TABLE IF NOT EXISTS time_rates (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    base_fare_id        UUID NOT NULL REFERENCES base_fares(id),
    time_of_day_start   TIME,
    time_of_day_end     TIME,
    day_of_week         INTEGER[],
    rate_per_minute     DECIMAL(8,2) NOT NULL,
    idle_rate_per_minute DECIMAL(8,2) DEFAULT 0
);

CREATE TABLE IF NOT EXISTS city_pricing (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    city_region_id      UUID NOT NULL REFERENCES city_regions(id),
    tax_rate            DECIMAL(5,4) NOT NULL DEFAULT 0,
    tax_components      JSONB,
    service_tax_pct     DECIMAL(5,2) DEFAULT 0,
    gst_pct             DECIMAL(5,2) DEFAULT 0,
    toll_enabled        BOOLEAN DEFAULT true,
    dynamic_pricing     BOOLEAN DEFAULT true,
    fare_cap_enabled    BOOLEAN DEFAULT false,
    max_surge_cap       DECIMAL(4,2) DEFAULT 3.00,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS surge_zones (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    h3_index            VARCHAR(20) NOT NULL,
    city_region_id      UUID REFERENCES city_regions(id),
    current_multiplier  DECIMAL(4,2) NOT NULL DEFAULT 1.00,
    supply_count        INTEGER,
    demand_count        INTEGER,
    supply_demand_ratio DECIMAL(6,3),
    computed_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at          TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_surge_zone ON surge_zones(h3_index);

CREATE TABLE IF NOT EXISTS surge_multipliers (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    surge_zone_id       UUID NOT NULL REFERENCES surge_zones(id),
    vehicle_type_id     UUID REFERENCES vehicle_types(id),
    multiplier          DECIMAL(4,2) NOT NULL,
    reason              VARCHAR(50) CHECK (reason IN ('demand','event','weather','time_of_day','manual')),
    override_by         UUID REFERENCES users(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS surge_history (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    h3_index            VARCHAR(20) NOT NULL,
    multiplier          DECIMAL(4,2) NOT NULL,
    supply_count        INTEGER,
    demand_count        INTEGER,
    ratio               DECIMAL(6,3),
    weather_factor      DECIMAL(4,2) DEFAULT 1.0,
    event_factor        DECIMAL(4,2) DEFAULT 1.0,
    recorded_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_surge_hist ON surge_history(h3_index, recorded_at DESC);

CREATE TABLE IF NOT EXISTS fare_estimations (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rider_id            UUID REFERENCES riders(id),
    pickup_location     GEOMETRY(Point, 4326) NOT NULL,
    dropoff_location    GEOMETRY(Point, 4326) NOT NULL,
    vehicle_type_id     UUID REFERENCES vehicle_types(id),
    estimated_distance_m INTEGER,
    estimated_duration_s INTEGER,
    base_fare           DECIMAL(10,2),
    surge_multiplier    DECIMAL(4,2),
    estimated_total     DECIMAL(10,2),
    fare_range_low      DECIMAL(10,2),
    fare_range_high     DECIMAL(10,2),
    valid_until         TIMESTAMPTZ NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS pricing_experiments (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    experiment_name     VARCHAR(200) NOT NULL,
    description         TEXT,
    variant_a           JSONB NOT NULL,
    variant_b           JSONB NOT NULL,
    allocation_pct      DECIMAL(5,2) DEFAULT 50.0,
    target_city         UUID REFERENCES city_regions(id),
    target_vehicle_type UUID REFERENCES vehicle_types(id),
    status              VARCHAR(20) DEFAULT 'draft'
                        CHECK (status IN ('draft','running','paused','completed','cancelled')),
    started_at          TIMESTAMPTZ,
    ended_at            TIMESTAMPTZ,
    results             JSONB,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS toll_rates (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    toll_name           VARCHAR(200) NOT NULL,
    location            GEOMETRY(Point, 4326) NOT NULL,
    toll_road_segment   GEOMETRY(LineString, 4326),
    vehicle_category    VARCHAR(30),
    rate                DECIMAL(10,2) NOT NULL,
    currency            VARCHAR(3) DEFAULT 'INR',
    effective_from      TIMESTAMPTZ,
    effective_until     TIMESTAMPTZ,
    is_active           BOOLEAN DEFAULT true
);
CREATE INDEX IF NOT EXISTS idx_toll_loc ON toll_rates USING GIST(location);

CREATE TABLE IF NOT EXISTS fare_caps (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    city_region_id      UUID NOT NULL REFERENCES city_regions(id),
    vehicle_type_id     UUID REFERENCES vehicle_types(id),
    max_fare_per_km     DECIMAL(8,2),
    max_total_fare      DECIMAL(10,2),
    max_surge           DECIMAL(4,2) DEFAULT 3.00,
    regulatory_ref      VARCHAR(200),
    effective_from      TIMESTAMPTZ NOT NULL,
    effective_until     TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS booking_fees (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    city_region_id      UUID NOT NULL REFERENCES city_regions(id),
    vehicle_type_id     UUID REFERENCES vehicle_types(id),
    fee_amount          DECIMAL(10,2) NOT NULL,
    fee_type            VARCHAR(20) CHECK (fee_type IN ('flat','percentage')),
    description         VARCHAR(200),
    is_active           BOOLEAN DEFAULT true,
    effective_from      TIMESTAMPTZ NOT NULL
);

-- Pricing Service: 14 tables total
