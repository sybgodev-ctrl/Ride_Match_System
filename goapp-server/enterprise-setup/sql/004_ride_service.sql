-- ============================================================
-- GoApp Enterprise Schema: 004 - Ride Service (Core Domain)
-- Domain: Ride Service (28 tables)
-- ============================================================

CREATE EXTENSION IF NOT EXISTS postgis;

-- ──────────────────────────────────────────────────────
-- Ride Lifecycle Tables
-- ──────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS rides (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_number         VARCHAR(20) UNIQUE NOT NULL,
    rider_id            UUID NOT NULL REFERENCES riders(id),
    driver_id           UUID REFERENCES drivers(id),
    vehicle_id          UUID REFERENCES vehicles(id),
    vehicle_type_id     UUID REFERENCES vehicle_types(id),

    -- Ride Type
    ride_type           VARCHAR(30) NOT NULL
                        CHECK (ride_type IN ('on_demand','scheduled','shared','rental','intercity')),
    is_shared           BOOLEAN DEFAULT false,

    -- Locations
    pickup_lat          DECIMAL(10,7) NOT NULL,
    pickup_lng          DECIMAL(10,7) NOT NULL,
    pickup_address      TEXT,
    pickup_place_id     VARCHAR(200),
    dropoff_lat         DECIMAL(10,7),
    dropoff_lng         DECIMAL(10,7),
    dropoff_address     TEXT,
    dropoff_place_id    VARCHAR(200),

    -- Multi-stop support
    waypoints           JSONB DEFAULT '[]',

    -- Status
    status              VARCHAR(30) NOT NULL DEFAULT 'requested'
                        CHECK (status IN ('requested','searching','driver_assigned','driver_arriving',
                                          'driver_arrived','ride_started','in_progress','completing',
                                          'completed','cancelled','no_drivers','failed')),

    -- Distance & Time
    estimated_distance_m INTEGER,
    actual_distance_m    INTEGER,
    estimated_duration_s INTEGER,
    actual_duration_s    INTEGER,

    -- Fare
    estimated_fare      DECIMAL(10,2),
    actual_fare         DECIMAL(10,2),
    currency            VARCHAR(3) DEFAULT 'INR',
    surge_multiplier    DECIMAL(4,2) DEFAULT 1.00,

    -- Scheduling
    scheduled_at        TIMESTAMPTZ,

    -- Timestamps
    requested_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    accepted_at         TIMESTAMPTZ,
    arrived_at          TIMESTAMPTZ,
    started_at          TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,
    cancelled_at        TIMESTAMPTZ,

    -- Metadata
    source_app          VARCHAR(20) CHECK (source_app IN ('rider_app','web','api','corporate')),
    payment_method_id   UUID,
    promo_code_id       UUID,
    corporate_id        UUID,
    idempotency_key     VARCHAR(200) UNIQUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_rides_rider ON rides(rider_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_rides_driver ON rides(driver_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_rides_status ON rides(status);
CREATE INDEX IF NOT EXISTS idx_rides_created ON rides(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_rides_scheduled ON rides(scheduled_at) WHERE ride_type = 'scheduled';

CREATE TABLE IF NOT EXISTS ride_requests (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id             UUID NOT NULL REFERENCES rides(id),
    rider_id            UUID NOT NULL REFERENCES riders(id),
    pickup_location     GEOMETRY(Point, 4326) NOT NULL,
    dropoff_location    GEOMETRY(Point, 4326),
    pickup_h3_index     VARCHAR(20) NOT NULL,
    dropoff_h3_index    VARCHAR(20),
    requested_vehicle_types UUID[] NOT NULL,
    passenger_count     INTEGER DEFAULT 1,
    special_requests    JSONB,
    fare_estimate_id    UUID,
    search_radius_m     INTEGER DEFAULT 5000,
    max_wait_seconds    INTEGER DEFAULT 300,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_ride_req_h3 ON ride_requests(pickup_h3_index);

CREATE TABLE IF NOT EXISTS ride_status_history (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id             UUID NOT NULL REFERENCES rides(id),
    old_status          VARCHAR(30),
    new_status          VARCHAR(30) NOT NULL,
    actor_type          VARCHAR(20) CHECK (actor_type IN ('system','driver','rider','admin')),
    actor_id            UUID,
    reason              TEXT,
    metadata            JSONB,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_ride_status_hist ON ride_status_history(ride_id, created_at);

CREATE TABLE IF NOT EXISTS ride_routes (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id             UUID NOT NULL REFERENCES rides(id),
    route_type          VARCHAR(20) CHECK (route_type IN ('estimated','actual','alternative')),
    polyline            TEXT,
    route_geometry      GEOMETRY(LineString, 4326),
    distance_m          INTEGER,
    duration_s          INTEGER,
    waypoints           JSONB,
    traffic_model       VARCHAR(20),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_ride_routes ON ride_routes(ride_id);

CREATE TABLE IF NOT EXISTS ride_fare_breakdown (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id             UUID NOT NULL UNIQUE REFERENCES rides(id),
    base_fare           DECIMAL(10,2) NOT NULL,
    distance_fare       DECIMAL(10,2) NOT NULL,
    time_fare           DECIMAL(10,2) NOT NULL,
    surge_amount        DECIMAL(10,2) DEFAULT 0,
    surge_multiplier    DECIMAL(4,2) DEFAULT 1.00,
    toll_charges        DECIMAL(10,2) DEFAULT 0,
    parking_fees        DECIMAL(10,2) DEFAULT 0,
    taxes               DECIMAL(10,2) DEFAULT 0,
    tax_breakdown       JSONB,
    booking_fee         DECIMAL(10,2) DEFAULT 0,
    platform_fee        DECIMAL(10,2) DEFAULT 0,
    tip_amount          DECIMAL(10,2) DEFAULT 0,
    promo_discount      DECIMAL(10,2) DEFAULT 0,
    wallet_deduction    DECIMAL(10,2) DEFAULT 0,
    total_fare          DECIMAL(10,2) NOT NULL,
    driver_payout       DECIMAL(10,2),
    platform_commission DECIMAL(10,2),
    currency            VARCHAR(3) DEFAULT 'INR',
    calculated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ride_cancellations (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id             UUID NOT NULL REFERENCES rides(id),
    cancelled_by        VARCHAR(20) NOT NULL CHECK (cancelled_by IN ('rider','driver','system')),
    canceller_id        UUID,
    reason_code         VARCHAR(50),
    reason_text         TEXT,
    cancellation_fee    DECIMAL(10,2) DEFAULT 0,
    is_fee_waived       BOOLEAN DEFAULT false,
    waiver_reason       TEXT,
    time_since_request  INTEGER,
    time_since_accept   INTEGER,
    driver_distance_m   INTEGER,
    cancelled_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_ride_cancel ON ride_cancellations(ride_id);

CREATE TABLE IF NOT EXISTS ride_disputes (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id             UUID NOT NULL REFERENCES rides(id),
    raised_by           UUID NOT NULL REFERENCES users(id),
    dispute_type        VARCHAR(50) NOT NULL
                        CHECK (dispute_type IN ('fare','route','safety','behavior',
                                                'damage','lost_item','overcharge','other')),
    description         TEXT NOT NULL,
    evidence_urls       TEXT[],
    status              VARCHAR(20) DEFAULT 'open'
                        CHECK (status IN ('open','investigating','resolved','escalated','closed')),
    assigned_to         UUID REFERENCES users(id),
    resolution          TEXT,
    refund_amount       DECIMAL(10,2),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at         TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS ride_feedback (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id             UUID NOT NULL REFERENCES rides(id),
    from_user_id        UUID NOT NULL REFERENCES users(id),
    to_user_id          UUID NOT NULL REFERENCES users(id),
    rating              DECIMAL(2,1) NOT NULL CHECK (rating >= 1 AND rating <= 5),
    tags                TEXT[],
    comment             TEXT,
    is_flagged          BOOLEAN DEFAULT false,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_ride_feedback ON ride_feedback(ride_id);

CREATE TABLE IF NOT EXISTS ride_events (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id             UUID NOT NULL REFERENCES rides(id),
    event_type          VARCHAR(50) NOT NULL,
    event_data          JSONB NOT NULL,
    actor_type          VARCHAR(20),
    actor_id            UUID,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_ride_events ON ride_events(ride_id, created_at);
-- Event types: route_deviated, long_stop, speed_alert, harsh_brake, sos_triggered

CREATE TABLE IF NOT EXISTS ride_safety_events (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id             UUID NOT NULL REFERENCES rides(id),
    event_type          VARCHAR(50) NOT NULL
                        CHECK (event_type IN ('sos','crash_detected','route_deviation',
                                              'long_stop','speed_violation','driver_switch',
                                              'unsafe_behavior')),
    severity            VARCHAR(10) CHECK (severity IN ('low','medium','high','critical')),
    location            GEOMETRY(Point, 4326),
    details             JSONB,
    auto_actions_taken  JSONB,
    reported_by         UUID,
    resolved            BOOLEAN DEFAULT false,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_ride_safety ON ride_safety_events(ride_id);
CREATE INDEX IF NOT EXISTS idx_ride_safety_sev ON ride_safety_events(severity) WHERE resolved = false;

CREATE TABLE IF NOT EXISTS ride_timestamps (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id             UUID NOT NULL UNIQUE REFERENCES rides(id),
    requested_at        TIMESTAMPTZ,
    dispatched_at       TIMESTAMPTZ,
    driver_notified_at  TIMESTAMPTZ,
    driver_accepted_at  TIMESTAMPTZ,
    driver_arriving_at  TIMESTAMPTZ,
    driver_arrived_at   TIMESTAMPTZ,
    otp_verified_at     TIMESTAMPTZ,
    ride_started_at     TIMESTAMPTZ,
    ride_completed_at   TIMESTAMPTZ,
    payment_initiated_at TIMESTAMPTZ,
    payment_completed_at TIMESTAMPTZ,
    rated_at            TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS ride_metadata (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id             UUID NOT NULL UNIQUE REFERENCES rides(id),
    weather_conditions  JSONB,
    traffic_conditions  JSONB,
    route_options_shown INTEGER,
    eta_accuracy_pct    DECIMAL(5,2),
    fare_accuracy_pct   DECIMAL(5,2),
    app_version_rider   VARCHAR(20),
    app_version_driver  VARCHAR(20),
    experiment_flags    JSONB,
    ab_test_group       VARCHAR(50)
);

CREATE TABLE IF NOT EXISTS ride_otp (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id             UUID NOT NULL REFERENCES rides(id),
    otp_code            VARCHAR(6) NOT NULL,
    is_verified         BOOLEAN DEFAULT false,
    attempts            INTEGER DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at          TIMESTAMPTZ NOT NULL,
    verified_at         TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS ride_shared_pool (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pool_id             VARCHAR(50) NOT NULL,
    ride_id             UUID NOT NULL REFERENCES rides(id),
    rider_id            UUID NOT NULL REFERENCES riders(id),
    pickup_order        INTEGER NOT NULL,
    dropoff_order       INTEGER NOT NULL,
    detour_factor       DECIMAL(4,2),
    discount_pct        DECIMAL(5,2),
    joined_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_shared_pool ON ride_shared_pool(pool_id);

-- Additional ride tables for completeness

CREATE TABLE IF NOT EXISTS ride_tips (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id             UUID NOT NULL REFERENCES rides(id),
    rider_id            UUID NOT NULL REFERENCES riders(id),
    driver_id           UUID NOT NULL REFERENCES drivers(id),
    amount              DECIMAL(10,2) NOT NULL,
    status              VARCHAR(20) DEFAULT 'pending'
                        CHECK (status IN ('pending','completed','failed')),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ride_toll_charges (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id             UUID NOT NULL REFERENCES rides(id),
    toll_name           VARCHAR(200),
    amount              DECIMAL(10,2) NOT NULL,
    location            GEOMETRY(Point, 4326),
    detected_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ride_waiting_charges (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id             UUID NOT NULL REFERENCES rides(id),
    wait_type           VARCHAR(30) CHECK (wait_type IN ('pickup_wait','stop_wait','traffic_wait')),
    start_time          TIMESTAMPTZ NOT NULL,
    end_time            TIMESTAMPTZ,
    duration_seconds    INTEGER,
    charge_amount       DECIMAL(10,2),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ride_stops (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id             UUID NOT NULL REFERENCES rides(id),
    stop_order          INTEGER NOT NULL,
    latitude            DECIMAL(10,7) NOT NULL,
    longitude           DECIMAL(10,7) NOT NULL,
    address             TEXT,
    arrived_at          TIMESTAMPTZ,
    departed_at         TIMESTAMPTZ,
    wait_time_seconds   INTEGER,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ride_ratings_summary (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id             UUID NOT NULL UNIQUE REFERENCES rides(id),
    rider_to_driver     DECIMAL(2,1),
    driver_to_rider     DECIMAL(2,1),
    rider_tags          TEXT[],
    driver_tags         TEXT[],
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ride_receipts (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id             UUID NOT NULL UNIQUE REFERENCES rides(id),
    receipt_number      VARCHAR(50) UNIQUE NOT NULL,
    receipt_url         TEXT,
    line_items          JSONB NOT NULL,
    total_amount        DECIMAL(10,2) NOT NULL,
    currency            VARCHAR(3) DEFAULT 'INR',
    generated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sent_at             TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS ride_route_deviations (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id             UUID NOT NULL REFERENCES rides(id),
    deviation_point     GEOMETRY(Point, 4326),
    expected_route_distance_m INTEGER,
    actual_distance_m   INTEGER,
    deviation_pct       DECIMAL(5,2),
    detected_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    acknowledged        BOOLEAN DEFAULT false
);

CREATE TABLE IF NOT EXISTS ride_driver_location_trail (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id             UUID NOT NULL REFERENCES rides(id),
    driver_id           UUID NOT NULL,
    location            GEOMETRY(Point, 4326) NOT NULL,
    speed_kmh           DECIMAL(6,2),
    heading             DECIMAL(5,2),
    recorded_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_ride_trail ON ride_driver_location_trail(ride_id, recorded_at);

-- Ride Service: 28 tables total
