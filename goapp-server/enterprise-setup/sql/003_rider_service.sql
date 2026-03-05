-- ============================================================
-- GoApp Enterprise Schema: 003 - Rider Service
-- Domain: Rider Service (10 tables)
-- ============================================================

CREATE TABLE IF NOT EXISTS riders (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL UNIQUE REFERENCES users(id),
    default_payment_id  UUID,
    home_address        JSONB,
    work_address        JSONB,
    rider_tier          VARCHAR(20) DEFAULT 'standard'
                        CHECK (rider_tier IN ('standard','silver','gold','platinum')),
    total_rides         INTEGER DEFAULT 0,
    lifetime_spend      DECIMAL(12,2) DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS rider_profiles (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rider_id            UUID NOT NULL REFERENCES riders(id),
    accessibility_needs JSONB,
    preferred_vehicle   UUID REFERENCES vehicle_types(id),
    preferred_language  VARCHAR(10) DEFAULT 'en',
    emergency_contact   JSONB,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS rider_ratings (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rider_id            UUID NOT NULL REFERENCES riders(id),
    ride_id             UUID NOT NULL,
    driver_id           UUID NOT NULL,
    rating              DECIMAL(2,1) NOT NULL CHECK (rating >= 1 AND rating <= 5),
    tags                TEXT[],
    comment             TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_rider_ratings ON rider_ratings(rider_id, created_at DESC);

CREATE TABLE IF NOT EXISTS rider_preferences (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rider_id            UUID NOT NULL REFERENCES riders(id),
    preference_key      VARCHAR(100) NOT NULL,
    preference_value    JSONB NOT NULL,
    UNIQUE(rider_id, preference_key)
);
-- Keys: ride_silence, temperature, music_genre, conversation_level, route_preference

CREATE TABLE IF NOT EXISTS rider_saved_places (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rider_id            UUID NOT NULL REFERENCES riders(id),
    label               VARCHAR(50) NOT NULL,
    name                VARCHAR(200),
    address             TEXT NOT NULL,
    latitude            DECIMAL(10,7) NOT NULL,
    longitude           DECIMAL(10,7) NOT NULL,
    place_id            VARCHAR(200),
    icon                VARCHAR(30) DEFAULT 'pin',
    sort_order          INTEGER DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_rider_saved ON rider_saved_places(rider_id);

CREATE TABLE IF NOT EXISTS rider_trip_history (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rider_id            UUID NOT NULL REFERENCES riders(id),
    ride_id             UUID NOT NULL,
    pickup_address      TEXT,
    dropoff_address     TEXT,
    fare_amount         DECIMAL(10,2),
    rating_given        DECIMAL(2,1),
    completed_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_rider_history ON rider_trip_history(rider_id, created_at DESC);

CREATE TABLE IF NOT EXISTS rider_behavior_metrics (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rider_id            UUID NOT NULL REFERENCES riders(id),
    metric_date         DATE NOT NULL,
    rides_taken         INTEGER DEFAULT 0,
    cancellations       INTEGER DEFAULT 0,
    no_shows            INTEGER DEFAULT 0,
    avg_rating_given    DECIMAL(3,2),
    avg_wait_tolerance  INTEGER,
    peak_hour_rides     INTEGER DEFAULT 0,
    total_spend         DECIMAL(10,2) DEFAULT 0,
    UNIQUE(rider_id, metric_date)
);

CREATE TABLE IF NOT EXISTS rider_favorites (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rider_id            UUID NOT NULL REFERENCES riders(id),
    driver_id           UUID NOT NULL REFERENCES drivers(id),
    reason              TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(rider_id, driver_id)
);

CREATE TABLE IF NOT EXISTS rider_blocklist (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rider_id            UUID NOT NULL REFERENCES riders(id),
    driver_id           UUID NOT NULL REFERENCES drivers(id),
    reason              TEXT,
    blocked_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(rider_id, driver_id)
);

CREATE TABLE IF NOT EXISTS rider_loyalty_points (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rider_id            UUID NOT NULL REFERENCES riders(id),
    points_balance      INTEGER DEFAULT 0,
    lifetime_earned     INTEGER DEFAULT 0,
    lifetime_redeemed   INTEGER DEFAULT 0,
    tier_expiry         DATE,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Rider Service: 10 tables total
