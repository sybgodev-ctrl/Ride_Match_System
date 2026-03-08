-- ============================================================
-- GoApp Enterprise Schema: 005 - Dispatch / Matching Engine
-- Domain: Dispatch & Matching (18 tables)
-- This is the MOST CRITICAL domain for ride-hailing operations
-- ============================================================

-- ═══════════════════════════════════════════════════════
-- PHASE 1: SUPPLY TRACKING
-- ═══════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS driver_location_cache (
    driver_id           UUID PRIMARY KEY REFERENCES drivers(id),
    location            GEOMETRY(Point, 4326) NOT NULL,
    h3_index_res7       VARCHAR(20) NOT NULL,
    h3_index_res8       VARCHAR(20) NOT NULL,
    h3_index_res9       VARCHAR(20) NOT NULL,
    heading             DECIMAL(5,2),
    speed_kmh           DECIMAL(6,2),
    accuracy_m          DECIMAL(6,2),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_dlc_h3_r8 ON driver_location_cache(h3_index_res8);
CREATE INDEX IF NOT EXISTS idx_dlc_h3_r9 ON driver_location_cache(h3_index_res9);
CREATE INDEX IF NOT EXISTS idx_dlc_geo ON driver_location_cache USING GIST(location);

CREATE TABLE IF NOT EXISTS driver_availability (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id           UUID NOT NULL REFERENCES drivers(id),
    is_available        BOOLEAN NOT NULL DEFAULT false,
    current_ride_id     UUID,
    vehicle_type_id     UUID REFERENCES vehicle_types(id),
    capacity_remaining  INTEGER DEFAULT 1,
    will_be_free_at     TIMESTAMPTZ,
    destination_bias    GEOMETRY(Point, 4326),
    last_ride_dropoff   GEOMETRY(Point, 4326),
    shift_end_time      TIMESTAMPTZ,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(driver_id)
);
CREATE INDEX IF NOT EXISTS idx_driver_avail ON driver_availability(is_available, vehicle_type_id);

CREATE TABLE IF NOT EXISTS driver_supply_snapshots (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    h3_index            VARCHAR(20) NOT NULL,
    resolution          INTEGER NOT NULL CHECK (resolution IN (7, 8, 9)),
    available_drivers   INTEGER NOT NULL,
    busy_drivers        INTEGER NOT NULL,
    total_drivers       INTEGER NOT NULL,
    vehicle_breakdown   JSONB,
    snapshot_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_supply_snap ON driver_supply_snapshots(h3_index, snapshot_at DESC);

-- ═══════════════════════════════════════════════════════
-- PHASE 2: DEMAND TRACKING
-- ═══════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS demand_forecasts (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    h3_index            VARCHAR(20) NOT NULL,
    resolution          INTEGER NOT NULL,
    forecast_for        TIMESTAMPTZ NOT NULL,
    predicted_requests  DECIMAL(8,2),
    confidence_lower    DECIMAL(8,2),
    confidence_upper    DECIMAL(8,2),
    model_version       VARCHAR(50),
    features_used       JSONB,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_demand_forecast ON demand_forecasts(h3_index, forecast_for);

CREATE TABLE IF NOT EXISTS demand_realtime (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    h3_index            VARCHAR(20) NOT NULL,
    resolution          INTEGER NOT NULL,
    active_requests     INTEGER NOT NULL DEFAULT 0,
    unfulfilled_requests INTEGER NOT NULL DEFAULT 0,
    avg_wait_seconds    INTEGER,
    window_start        TIMESTAMPTZ NOT NULL,
    window_end          TIMESTAMPTZ NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_demand_rt ON demand_realtime(h3_index, window_start DESC);

-- ═══════════════════════════════════════════════════════
-- PHASE 3: DISPATCH & MATCHING
-- ═══════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS dispatch_jobs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_request_id     UUID NOT NULL,
    ride_id             UUID NOT NULL REFERENCES rides(id),
    status              VARCHAR(30) NOT NULL DEFAULT 'created'
                        CHECK (status IN ('created','collecting','matching','dispatching',
                                          'assigned','exhausted','cancelled','expired')),

    -- Matching window (batch collection)
    batch_window_ms     INTEGER DEFAULT 2000,
    batch_started_at    TIMESTAMPTZ,
    batch_closed_at     TIMESTAMPTZ,

    -- Search parameters
    search_radius_m     INTEGER NOT NULL DEFAULT 5000,
    max_radius_m        INTEGER DEFAULT 10000,
    radius_expansion_step INTEGER DEFAULT 1000,
    current_radius_m    INTEGER,

    -- Results
    candidates_found    INTEGER DEFAULT 0,
    attempts_made       INTEGER DEFAULT 0,
    max_attempts        INTEGER DEFAULT 10,
    assigned_driver_id  UUID REFERENCES drivers(id),

    -- Timing
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    assigned_at         TIMESTAMPTZ,
    expired_at          TIMESTAMPTZ,
    ttl_seconds         INTEGER DEFAULT 300
);
CREATE INDEX IF NOT EXISTS idx_dispatch_status ON dispatch_jobs(status);
CREATE INDEX IF NOT EXISTS idx_dispatch_ride ON dispatch_jobs(ride_id);

CREATE TABLE IF NOT EXISTS dispatch_batches (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_window_start  TIMESTAMPTZ NOT NULL,
    batch_window_end    TIMESTAMPTZ NOT NULL,
    h3_region           VARCHAR(20) NOT NULL,
    requests_in_batch   INTEGER NOT NULL,
    drivers_in_batch    INTEGER NOT NULL,
    algorithm_used      VARCHAR(50) NOT NULL,
    optimization_score  DECIMAL(8,4),
    computation_ms      INTEGER,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_dispatch_batch ON dispatch_batches(batch_window_start);

CREATE TABLE IF NOT EXISTS dispatch_attempts (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dispatch_job_id     UUID NOT NULL REFERENCES dispatch_jobs(id),
    driver_id           UUID NOT NULL REFERENCES drivers(id),
    attempt_number      INTEGER NOT NULL,

    -- Driver state at dispatch time
    driver_location     GEOMETRY(Point, 4326),
    driver_h3_index     VARCHAR(20),
    distance_to_pickup_m INTEGER,
    eta_seconds         INTEGER,

    -- Scoring
    match_score         DECIMAL(8,4),
    score_breakdown     JSONB,

    -- Response
    status              VARCHAR(20) NOT NULL DEFAULT 'sent'
                        CHECK (status IN ('sent','seen','accepted','rejected','expired','cancelled')),
    response_time_ms    INTEGER,
    rejection_reason    VARCHAR(100),

    -- Timing
    sent_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    responded_at        TIMESTAMPTZ,
    expires_at          TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_dispatch_att_job ON dispatch_attempts(dispatch_job_id);
CREATE INDEX IF NOT EXISTS idx_dispatch_att_driver ON dispatch_attempts(driver_id, sent_at DESC);

CREATE TABLE IF NOT EXISTS dispatch_logs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dispatch_job_id     UUID NOT NULL REFERENCES dispatch_jobs(id),
    log_level           VARCHAR(10) CHECK (log_level IN ('debug','info','warn','error')),
    phase               VARCHAR(30),
    message             TEXT NOT NULL,
    details             JSONB,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_dispatch_log ON dispatch_logs(dispatch_job_id);

CREATE TABLE IF NOT EXISTS ride_driver_matches (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id             UUID NOT NULL REFERENCES rides(id),
    driver_id           UUID NOT NULL REFERENCES drivers(id),
    dispatch_job_id     UUID REFERENCES dispatch_jobs(id),
    match_type          VARCHAR(30) CHECK (match_type IN ('optimal','fallback','manual','rebalance')),
    match_score         DECIMAL(8,4),
    score_components    JSONB,
    eta_at_match        INTEGER,
    distance_at_match   INTEGER,
    matched_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_match_ride ON ride_driver_matches(ride_id);

CREATE TABLE IF NOT EXISTS driver_acceptance_history (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id           UUID NOT NULL REFERENCES drivers(id),
    dispatch_attempt_id UUID REFERENCES dispatch_attempts(id),
    ride_id             UUID REFERENCES rides(id),
    action              VARCHAR(20) NOT NULL CHECK (action IN ('accepted','rejected','expired','missed')),
    response_time_ms    INTEGER,
    reason              VARCHAR(100),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_accept_hist ON driver_acceptance_history(driver_id, created_at DESC);

CREATE TABLE IF NOT EXISTS driver_rejections (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id           UUID NOT NULL REFERENCES drivers(id),
    ride_id             UUID NOT NULL REFERENCES rides(id),
    reason_code         VARCHAR(50) NOT NULL,
    reason_text         TEXT,
    consecutive_rejects INTEGER DEFAULT 1,
    penalty_applied     BOOLEAN DEFAULT false,
    penalty_type        VARCHAR(50),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_driver_rejects ON driver_rejections(driver_id, created_at DESC);

CREATE TABLE IF NOT EXISTS matching_algorithm_metrics (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    algorithm_version   VARCHAR(50) NOT NULL,
    h3_region           VARCHAR(20),
    time_window         TSTZRANGE NOT NULL,
    total_requests      INTEGER,
    matched_requests    INTEGER,
    avg_match_time_ms   INTEGER,
    avg_eta_seconds     INTEGER,
    avg_match_score     DECIMAL(8,4),
    p50_wait_seconds    INTEGER,
    p90_wait_seconds    INTEGER,
    p99_wait_seconds    INTEGER,
    first_attempt_success_rate DECIMAL(5,2),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS matching_weights_config (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    config_name         VARCHAR(100) NOT NULL,
    city                VARCHAR(100),
    vehicle_type_id     UUID REFERENCES vehicle_types(id),

    -- Scoring weights (must sum to 1.0)
    weight_distance     DECIMAL(4,3) NOT NULL DEFAULT 0.30,
    weight_eta          DECIMAL(4,3) NOT NULL DEFAULT 0.25,
    weight_driver_rating DECIMAL(4,3) NOT NULL DEFAULT 0.15,
    weight_acceptance_rate DECIMAL(4,3) NOT NULL DEFAULT 0.10,
    weight_driver_idle_time DECIMAL(4,3) NOT NULL DEFAULT 0.10,
    weight_destination_bias DECIMAL(4,3) NOT NULL DEFAULT 0.05,
    weight_rider_preference DECIMAL(4,3) NOT NULL DEFAULT 0.05,

    -- Thresholds
    max_pickup_distance_m INTEGER DEFAULT 5000,
    max_eta_seconds     INTEGER DEFAULT 600,
    min_driver_rating   DECIMAL(3,2) DEFAULT 4.0,
    min_acceptance_rate DECIMAL(5,2) DEFAULT 50.0,

    is_active           BOOLEAN DEFAULT true,
    version             INTEGER DEFAULT 1,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS driver_eta_cache (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id           UUID NOT NULL REFERENCES drivers(id),
    destination_h3      VARCHAR(20) NOT NULL,
    eta_seconds         INTEGER NOT NULL,
    distance_m          INTEGER NOT NULL,
    route_polyline      TEXT,
    computed_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at          TIMESTAMPTZ NOT NULL,
    UNIQUE(driver_id, destination_h3)
);
CREATE INDEX IF NOT EXISTS idx_eta_cache ON driver_eta_cache(driver_id, destination_h3);

-- Dispatch / Matching Engine: 18 tables total
