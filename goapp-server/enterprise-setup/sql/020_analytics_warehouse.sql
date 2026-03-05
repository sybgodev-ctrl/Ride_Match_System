-- ============================================================
-- GoApp Enterprise Schema: 020 - Data Warehouse / Analytics
-- Domain: Analytics (22 tables)
-- Star schema: 8 fact tables + 6 dimension tables + 6 aggregates + 2 utility
-- ============================================================

-- ──────────────────────────────────────────────────────
-- Fact Tables
-- ──────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS fact_rides (
    ride_id             UUID PRIMARY KEY,
    ride_number         VARCHAR(20),
    rider_dim_id        UUID,
    driver_dim_id       UUID,
    vehicle_type_dim_id UUID,
    pickup_location_dim_id UUID,
    dropoff_location_dim_id UUID,
    time_dim_id         UUID,

    ride_type           VARCHAR(30),
    status              VARCHAR(30),
    distance_m          INTEGER,
    duration_s          INTEGER,
    wait_time_s         INTEGER,
    pickup_time_s       INTEGER,

    base_fare           DECIMAL(10,2),
    surge_multiplier    DECIMAL(4,2),
    total_fare          DECIMAL(10,2),
    driver_earnings     DECIMAL(10,2),
    platform_revenue    DECIMAL(10,2),
    promo_discount      DECIMAL(10,2),

    match_score         DECIMAL(8,4),
    dispatch_attempts   INTEGER,

    requested_at        TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,
    etl_loaded_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS fact_payments (
    payment_id          UUID PRIMARY KEY,
    ride_id             UUID,
    rider_dim_id        UUID,
    time_dim_id         UUID,

    payment_method      VARCHAR(30),
    gateway             VARCHAR(50),
    amount              DECIMAL(10,2),
    currency            VARCHAR(3),
    status              VARCHAR(20),

    processing_time_ms  INTEGER,
    retry_count         INTEGER,

    created_at          TIMESTAMPTZ,
    etl_loaded_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS fact_driver_activity (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_dim_id       UUID,
    time_dim_id         UUID,
    location_dim_id     UUID,

    activity_date       DATE,
    online_minutes      INTEGER,
    idle_minutes        INTEGER,
    on_ride_minutes     INTEGER,
    rides_completed     INTEGER,
    rides_cancelled     INTEGER,
    acceptance_rate     DECIMAL(5,2),
    gross_earnings      DECIMAL(12,2),
    incentive_earnings  DECIMAL(12,2),

    etl_loaded_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS fact_user_sessions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_dim_id         UUID,
    time_dim_id         UUID,

    session_date        DATE,
    app_type            VARCHAR(20),
    session_duration_s  INTEGER,
    screens_viewed      INTEGER,
    rides_requested     INTEGER,
    rides_completed     INTEGER,
    search_count        INTEGER,

    etl_loaded_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS fact_dispatch (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id             UUID,
    time_dim_id         UUID,
    location_dim_id     UUID,

    algorithm_version   VARCHAR(50),
    candidates_evaluated INTEGER,
    attempts_made       INTEGER,
    match_time_ms       INTEGER,
    success             BOOLEAN,
    final_eta_s         INTEGER,

    etl_loaded_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS fact_surge (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    location_dim_id     UUID,
    time_dim_id         UUID,

    h3_index            VARCHAR(20),
    multiplier          DECIMAL(4,2),
    supply_count        INTEGER,
    demand_count        INTEGER,
    supply_demand_ratio DECIMAL(6,3),

    recorded_at         TIMESTAMPTZ,
    etl_loaded_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS fact_fraud (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_dim_id         UUID,
    time_dim_id         UUID,

    fraud_type          VARCHAR(50),
    severity            VARCHAR(10),
    confirmed           BOOLEAN,
    amount_involved     DECIMAL(12,2),

    detected_at         TIMESTAMPTZ,
    etl_loaded_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS fact_support (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_dim_id         UUID,
    agent_dim_id        UUID,
    time_dim_id         UUID,

    category            VARCHAR(100),
    priority            VARCHAR(10),
    resolution_time_min INTEGER,
    messages_count      INTEGER,
    csat_rating         INTEGER,

    created_at          TIMESTAMPTZ,
    etl_loaded_at       TIMESTAMPTZ DEFAULT NOW()
);

-- ──────────────────────────────────────────────────────
-- Dimension Tables (SCD Type 2 where applicable)
-- ──────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS dim_users (
    dim_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL,
    user_type           VARCHAR(20),
    city                VARCHAR(100),
    country             VARCHAR(50),
    registration_date   DATE,
    tier                VARCHAR(20),
    is_active           BOOLEAN,
    valid_from          TIMESTAMPTZ NOT NULL,
    valid_to            TIMESTAMPTZ,
    is_current          BOOLEAN DEFAULT true
);

CREATE TABLE IF NOT EXISTS dim_drivers (
    dim_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id           UUID NOT NULL,
    driver_type         VARCHAR(30),
    city                VARCHAR(100),
    avg_rating          DECIMAL(3,2),
    total_rides         INTEGER,
    experience_months   INTEGER,
    valid_from          TIMESTAMPTZ NOT NULL,
    valid_to            TIMESTAMPTZ,
    is_current          BOOLEAN DEFAULT true
);

CREATE TABLE IF NOT EXISTS dim_locations (
    dim_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    h3_index            VARCHAR(20) NOT NULL,
    city                VARCHAR(100),
    region              VARCHAR(100),
    country             VARCHAR(50),
    zone_type           VARCHAR(30),
    latitude            DECIMAL(10,7),
    longitude           DECIMAL(10,7)
);

CREATE TABLE IF NOT EXISTS dim_time (
    dim_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_date           DATE NOT NULL UNIQUE,
    year                INTEGER,
    quarter             INTEGER,
    month               INTEGER,
    week                INTEGER,
    day_of_week         INTEGER,
    day_name            VARCHAR(10),
    is_weekend          BOOLEAN,
    is_holiday          BOOLEAN,
    holiday_name        VARCHAR(100),
    hour                INTEGER,
    time_of_day         VARCHAR(20)
);

CREATE TABLE IF NOT EXISTS dim_vehicle_types (
    dim_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_type_id     UUID NOT NULL,
    name                VARCHAR(50),
    category            VARCHAR(30),
    max_passengers      INTEGER,
    valid_from          TIMESTAMPTZ NOT NULL,
    is_current          BOOLEAN DEFAULT true
);

CREATE TABLE IF NOT EXISTS dim_promo_campaigns (
    dim_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id         UUID NOT NULL,
    campaign_name       VARCHAR(200),
    campaign_type       VARCHAR(30),
    discount_type       VARCHAR(20),
    start_date          DATE,
    end_date            DATE
);

-- ──────────────────────────────────────────────────────
-- Analytics Aggregates
-- ──────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS agg_daily_city_metrics (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    metric_date         DATE NOT NULL,
    city_region_id      UUID NOT NULL,
    total_rides         INTEGER,
    completed_rides     INTEGER,
    cancelled_rides     INTEGER,
    total_revenue       DECIMAL(14,2),
    total_driver_pay    DECIMAL(14,2),
    avg_fare            DECIMAL(10,2),
    avg_surge           DECIMAL(4,2),
    avg_wait_time_s     INTEGER,
    avg_ride_distance_m INTEGER,
    unique_riders       INTEGER,
    unique_drivers      INTEGER,
    new_riders          INTEGER,
    UNIQUE(metric_date, city_region_id)
);

CREATE TABLE IF NOT EXISTS agg_hourly_supply_demand (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hour_start          TIMESTAMPTZ NOT NULL,
    city_region_id      UUID NOT NULL,
    h3_index            VARCHAR(20),
    supply_drivers      INTEGER,
    demand_requests     INTEGER,
    fulfilled_requests  INTEGER,
    avg_surge           DECIMAL(4,2),
    avg_eta_s           INTEGER,
    UNIQUE(hour_start, city_region_id, h3_index)
);

CREATE TABLE IF NOT EXISTS agg_driver_cohort_analysis (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cohort_month        DATE NOT NULL,
    months_since_join   INTEGER NOT NULL,
    drivers_count       INTEGER,
    active_drivers      INTEGER,
    avg_rides_per_driver DECIMAL(8,2),
    avg_earnings        DECIMAL(12,2),
    retention_rate      DECIMAL(5,2),
    churn_rate          DECIMAL(5,2)
);

CREATE TABLE IF NOT EXISTS agg_rider_cohort_analysis (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cohort_month        DATE NOT NULL,
    months_since_join   INTEGER NOT NULL,
    riders_count        INTEGER,
    active_riders       INTEGER,
    avg_rides_per_rider DECIMAL(8,2),
    avg_spend           DECIMAL(12,2),
    retention_rate      DECIMAL(5,2)
);

-- ──────────────────────────────────────────────────────
-- ML & ETL Support
-- ──────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS ml_feature_store (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_type         VARCHAR(30) NOT NULL,
    entity_id           UUID NOT NULL,
    feature_name        VARCHAR(100) NOT NULL,
    feature_value       DECIMAL(20,6),
    feature_vector      JSONB,
    computed_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(entity_type, entity_id, feature_name)
);

CREATE TABLE IF NOT EXISTS etl_job_logs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_name            VARCHAR(100) NOT NULL,
    source_table        VARCHAR(100),
    target_table        VARCHAR(100),
    records_processed   BIGINT,
    records_inserted    BIGINT,
    records_updated     BIGINT,
    records_failed      BIGINT,
    status              VARCHAR(20),
    started_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at        TIMESTAMPTZ,
    error_message       TEXT
);

-- Analytics / Data Warehouse: 22 tables total
