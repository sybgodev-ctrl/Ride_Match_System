-- ============================================================
-- GoApp Enterprise Schema: 006 - Location Service
-- Domain: Location Service (12 tables)
-- Requires: PostGIS extension
-- ============================================================

CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE IF NOT EXISTS driver_locations (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id           UUID NOT NULL REFERENCES drivers(id),
    location            GEOMETRY(Point, 4326) NOT NULL,
    h3_index            VARCHAR(20) NOT NULL,
    altitude            DECIMAL(8,2),
    heading             DECIMAL(5,2),
    speed_kmh           DECIMAL(6,2),
    accuracy_m          DECIMAL(6,2),
    battery_level       DECIMAL(5,2),
    source              VARCHAR(20) CHECK (source IN ('gps','network','fused','mock')),
    recorded_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- Partitioned by day for performance
CREATE INDEX IF NOT EXISTS idx_driver_loc ON driver_locations(driver_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_driver_loc_h3 ON driver_locations(h3_index);

CREATE TABLE IF NOT EXISTS driver_location_history (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id           UUID NOT NULL,
    ride_id             UUID,
    location            GEOMETRY(Point, 4326) NOT NULL,
    h3_index            VARCHAR(20) NOT NULL,
    speed_kmh           DECIMAL(6,2),
    heading             DECIMAL(5,2),
    recorded_at         TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_loc_hist ON driver_location_history(driver_id, recorded_at DESC);

CREATE TABLE IF NOT EXISTS ride_live_locations (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id             UUID NOT NULL,
    driver_id           UUID NOT NULL,
    location            GEOMETRY(Point, 4326) NOT NULL,
    speed_kmh           DECIMAL(6,2),
    heading             DECIMAL(5,2),
    distance_remaining_m INTEGER,
    eta_remaining_s     INTEGER,
    recorded_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_ride_live ON ride_live_locations(ride_id, recorded_at DESC);

CREATE TABLE IF NOT EXISTS location_update_logs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id           UUID NOT NULL,
    update_count        INTEGER,
    avg_interval_ms     INTEGER,
    dropped_updates     INTEGER,
    battery_drain_pct   DECIMAL(5,2),
    session_start       TIMESTAMPTZ NOT NULL,
    session_end         TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS geo_zones (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name                VARCHAR(200) NOT NULL,
    zone_type           VARCHAR(30) NOT NULL
                        CHECK (zone_type IN ('city','airport','station','mall','hospital',
                                             'event_venue','restricted','surge_zone','geo_fence')),
    boundary            GEOMETRY(Polygon, 4326) NOT NULL,
    h3_indices          TEXT[] NOT NULL,
    properties          JSONB,
    is_active           BOOLEAN DEFAULT true,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_geo_zones_boundary ON geo_zones USING GIST(boundary);
CREATE INDEX IF NOT EXISTS idx_geo_zones_type ON geo_zones(zone_type);

CREATE TABLE IF NOT EXISTS geo_fences (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    zone_id             UUID NOT NULL REFERENCES geo_zones(id),
    fence_type          VARCHAR(30) NOT NULL
                        CHECK (fence_type IN ('pickup_only','dropoff_only','no_service',
                                              'speed_limit','queue_zone','staging_area')),
    rules               JSONB NOT NULL,
    priority            INTEGER DEFAULT 0,
    is_active           BOOLEAN DEFAULT true,
    effective_from      TIMESTAMPTZ,
    effective_until     TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS city_regions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    city_name           VARCHAR(100) NOT NULL,
    country_code        VARCHAR(5) NOT NULL,
    timezone            VARCHAR(50) NOT NULL,
    currency            VARCHAR(3) NOT NULL,
    boundary            GEOMETRY(MultiPolygon, 4326),
    center_point        GEOMETRY(Point, 4326),
    is_active           BOOLEAN DEFAULT true,
    service_config      JSONB,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_city_regions ON city_regions(city_name);

CREATE TABLE IF NOT EXISTS traffic_conditions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    h3_index            VARCHAR(20) NOT NULL,
    speed_kmh_avg       DECIMAL(6,2),
    speed_kmh_freeflow  DECIMAL(6,2),
    congestion_level    VARCHAR(10) CHECK (congestion_level IN ('free','light','moderate','heavy','gridlock')),
    incident_count      INTEGER DEFAULT 0,
    sample_size         INTEGER,
    recorded_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_traffic ON traffic_conditions(h3_index, recorded_at DESC);

CREATE TABLE IF NOT EXISTS h3_hex_indices (
    h3_index            VARCHAR(20) PRIMARY KEY,
    resolution          INTEGER NOT NULL,
    parent_index        VARCHAR(20),
    center_lat          DECIMAL(10,7),
    center_lng          DECIMAL(10,7),
    city_region_id      UUID REFERENCES city_regions(id),
    zone_type           VARCHAR(30),
    is_serviceable      BOOLEAN DEFAULT true,
    properties          JSONB
);
CREATE INDEX IF NOT EXISTS idx_h3_parent ON h3_hex_indices(parent_index);
CREATE INDEX IF NOT EXISTS idx_h3_city ON h3_hex_indices(city_region_id);

CREATE TABLE IF NOT EXISTS location_snapshots (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    snapshot_type       VARCHAR(30) NOT NULL,
    h3_index            VARCHAR(20) NOT NULL,
    driver_count        INTEGER,
    rider_count         INTEGER,
    avg_speed           DECIMAL(6,2),
    data                JSONB,
    snapshot_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS route_cache (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    origin_h3           VARCHAR(20) NOT NULL,
    destination_h3      VARCHAR(20) NOT NULL,
    distance_m          INTEGER NOT NULL,
    duration_s          INTEGER NOT NULL,
    polyline            TEXT,
    computed_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at          TIMESTAMPTZ NOT NULL,
    UNIQUE(origin_h3, destination_h3)
);
CREATE INDEX IF NOT EXISTS idx_route_cache ON route_cache(origin_h3, destination_h3);

CREATE TABLE IF NOT EXISTS map_data_versions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    region              VARCHAR(100) NOT NULL,
    provider            VARCHAR(50) NOT NULL,
    version             VARCHAR(50) NOT NULL,
    tile_url            TEXT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Location Service: 12 tables total
