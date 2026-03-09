BEGIN;

CREATE TABLE IF NOT EXISTS zone_catalog (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    zone_code     VARCHAR(80) NOT NULL UNIQUE,
    zone_name     VARCHAR(160) NOT NULL,
    city          VARCHAR(100) NOT NULL,
    state         VARCHAR(100) NOT NULL,
    country       VARCHAR(80) NOT NULL,
    pincode       VARCHAR(20),
    center_lat    DECIMAL(10,7) NOT NULL,
    center_lng    DECIMAL(10,7) NOT NULL,
    radius_km     DECIMAL(8,3) NOT NULL CHECK (radius_km > 0),
    zone_level    VARCHAR(20) NOT NULL
                  CHECK (zone_level IN ('neighbourhood', 'suburb', 'corridor')),
    is_active     BOOLEAN NOT NULL DEFAULT true,
    source_name   VARCHAR(120),
    source_url    TEXT,
    source_ref    TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_zone_catalog_geo_lookup
  ON zone_catalog(is_active, city, state, country, pincode);
CREATE INDEX IF NOT EXISTS idx_zone_catalog_code
  ON zone_catalog(zone_code);

ALTER TABLE rides
  ADD COLUMN IF NOT EXISTS pickup_zone_id UUID REFERENCES zone_catalog(id),
  ADD COLUMN IF NOT EXISTS drop_zone_id   UUID REFERENCES zone_catalog(id);

CREATE INDEX IF NOT EXISTS idx_rides_pickup_zone_time
  ON rides(pickup_zone_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_rides_drop_zone_time
  ON rides(drop_zone_id, created_at DESC);

CREATE TABLE IF NOT EXISTS zone_metrics_hourly (
    zone_id          UUID NOT NULL REFERENCES zone_catalog(id),
    hour_start       TIMESTAMPTZ NOT NULL,
    requested_count  INTEGER NOT NULL DEFAULT 0,
    completed_count  INTEGER NOT NULL DEFAULT 0,
    cancelled_count  INTEGER NOT NULL DEFAULT 0,
    no_driver_count  INTEGER NOT NULL DEFAULT 0,
    unique_riders    INTEGER NOT NULL DEFAULT 0,
    avg_fare         DECIMAL(10,2),
    avg_wait_sec     INTEGER,
    avg_trip_sec     INTEGER,
    total_fare       DECIMAL(12,2) NOT NULL DEFAULT 0,
    total_wait_sec   BIGINT NOT NULL DEFAULT 0,
    total_trip_sec   BIGINT NOT NULL DEFAULT 0,
    fare_samples     INTEGER NOT NULL DEFAULT 0,
    wait_samples     INTEGER NOT NULL DEFAULT 0,
    trip_samples     INTEGER NOT NULL DEFAULT 0,
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY(zone_id, hour_start)
);

CREATE INDEX IF NOT EXISTS idx_zone_metrics_hourly_time
  ON zone_metrics_hourly(hour_start DESC);

CREATE TABLE IF NOT EXISTS zone_metrics_hourly_riders (
    zone_id     UUID NOT NULL REFERENCES zone_catalog(id),
    hour_start  TIMESTAMPTZ NOT NULL,
    rider_id    UUID NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY(zone_id, hour_start, rider_id)
);

CREATE TABLE IF NOT EXISTS zone_peak_windows_daily (
    zone_id            UUID NOT NULL REFERENCES zone_catalog(id),
    metric_date        DATE NOT NULL,
    hour_start         TIMESTAMPTZ NOT NULL,
    requested_count    INTEGER NOT NULL DEFAULT 0,
    completed_count    INTEGER NOT NULL DEFAULT 0,
    cancelled_count    INTEGER NOT NULL DEFAULT 0,
    completion_ratio   DECIMAL(6,4) NOT NULL DEFAULT 0,
    rank               INTEGER NOT NULL,
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY(zone_id, metric_date, hour_start)
);

CREATE INDEX IF NOT EXISTS idx_zone_peak_windows_daily_lookup
  ON zone_peak_windows_daily(metric_date, zone_id, rank);

INSERT INTO zone_catalog (
  zone_code, zone_name, city, state, country, pincode,
  center_lat, center_lng, radius_km, zone_level,
  source_name, source_url, source_ref
)
VALUES
  ('CHN-CENTRAL', 'Central', 'Chennai', 'Tamil Nadu', 'IN', '600003', 13.0827, 80.2707, 3.8, 'neighbourhood', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-EGMORE', 'Egmore', 'Chennai', 'Tamil Nadu', 'IN', '600008', 13.0732, 80.2609, 2.8, 'neighbourhood', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-TNAGAR', 'T. Nagar', 'Chennai', 'Tamil Nadu', 'IN', '600017', 13.0418, 80.2341, 3.0, 'neighbourhood', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-MYLAPORE', 'Mylapore', 'Chennai', 'Tamil Nadu', 'IN', '600004', 13.0339, 80.2619, 2.6, 'neighbourhood', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-TRIPLICANE', 'Triplicane', 'Chennai', 'Tamil Nadu', 'IN', '600005', 13.0569, 80.2786, 2.0, 'neighbourhood', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-NUNGAMBAKKAM', 'Nungambakkam', 'Chennai', 'Tamil Nadu', 'IN', '600006', 13.0606, 80.2496, 2.5, 'neighbourhood', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-KODAMBAKKAM', 'Kodambakkam', 'Chennai', 'Tamil Nadu', 'IN', '600024', 13.0512, 80.2210, 2.5, 'neighbourhood', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-ANNA-NAGAR', 'Anna Nagar', 'Chennai', 'Tamil Nadu', 'IN', '600040', 13.0850, 80.2101, 3.2, 'neighbourhood', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-ADYAR', 'Adyar', 'Chennai', 'Tamil Nadu', 'IN', '600020', 13.0012, 80.2565, 2.8, 'neighbourhood', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-GUINDY', 'Guindy', 'Chennai', 'Tamil Nadu', 'IN', '600032', 13.0067, 80.2206, 3.2, 'neighbourhood', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-SAIDAPET', 'Saidapet', 'Chennai', 'Tamil Nadu', 'IN', '600015', 13.0223, 80.2231, 2.4, 'neighbourhood', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-TEYNAMPET', 'Teynampet', 'Chennai', 'Tamil Nadu', 'IN', '600018', 13.0412, 80.2505, 2.2, 'neighbourhood', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-THIRUVANMIYUR', 'Thiruvanmiyur', 'Chennai', 'Tamil Nadu', 'IN', '600041', 12.9830, 80.2594, 2.8, 'neighbourhood', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-VELACHERY', 'Velachery', 'Chennai', 'Tamil Nadu', 'IN', '600042', 12.9755, 80.2211, 3.0, 'neighbourhood', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-MADIPAKKAM', 'Madipakkam', 'Chennai', 'Tamil Nadu', 'IN', '600091', 12.9656, 80.1986, 2.5, 'neighbourhood', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-KEELKATTALAI', 'Keelkattalai', 'Chennai', 'Tamil Nadu', 'IN', '600117', 12.9559, 80.1973, 2.1, 'neighbourhood', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-PERUNGUDI', 'Perungudi', 'Chennai', 'Tamil Nadu', 'IN', '600096', 12.9629, 80.2411, 2.7, 'neighbourhood', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-THORAIPAKKAM', 'Thoraipakkam', 'Chennai', 'Tamil Nadu', 'IN', '600097', 12.9488, 80.2414, 2.7, 'neighbourhood', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-SHOLINGANALLUR', 'Sholinganallur', 'Chennai', 'Tamil Nadu', 'IN', '600097', 12.9010, 80.2279, 3.8, 'suburb', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-KARAPAKKAM', 'Karapakkam', 'Chennai', 'Tamil Nadu', 'IN', '600097', 12.9158, 80.2299, 2.8, 'neighbourhood', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-SIRUSERI', 'Siruseri', 'Chennai', 'Tamil Nadu', 'IN', '603103', 12.8234, 80.2295, 4.5, 'suburb', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-NAVALUR', 'Navalur', 'Chennai', 'Tamil Nadu', 'IN', '603103', 12.8459, 80.2260, 3.5, 'suburb', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-MEDAVAKKAM', 'Medavakkam', 'Chennai', 'Tamil Nadu', 'IN', '600100', 12.9215, 80.1926, 3.2, 'suburb', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-TAMBARAM', 'Tambaram', 'Chennai', 'Tamil Nadu', 'IN', '600045', 12.9249, 80.1000, 4.5, 'suburb', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-CHROMEPET', 'Chromepet', 'Chennai', 'Tamil Nadu', 'IN', '600044', 12.9516, 80.1455, 3.0, 'suburb', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-PALLAVARAM', 'Pallavaram', 'Chennai', 'Tamil Nadu', 'IN', '600043', 12.9675, 80.1491, 3.0, 'suburb', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-AIRPORT', 'Airport', 'Chennai', 'Tamil Nadu', 'IN', '600016', 12.9941, 80.1709, 3.5, 'neighbourhood', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-PORUR', 'Porur', 'Chennai', 'Tamil Nadu', 'IN', '600116', 13.0381, 80.1565, 3.2, 'suburb', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-VADAPALANI', 'Vadapalani', 'Chennai', 'Tamil Nadu', 'IN', '600026', 13.0500, 80.2121, 2.3, 'neighbourhood', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-AMBATTUR', 'Ambattur', 'Chennai', 'Tamil Nadu', 'IN', '600053', 13.1143, 80.1548, 4.0, 'suburb', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-AVADI', 'Avadi', 'Chennai', 'Tamil Nadu', 'IN', '600054', 13.1147, 80.1098, 4.0, 'suburb', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-REDHILLS', 'Red Hills', 'Chennai', 'Tamil Nadu', 'IN', '600052', 13.1913, 80.1850, 4.5, 'suburb', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-WASHERMANPET', 'Washermanpet', 'Chennai', 'Tamil Nadu', 'IN', '600021', 13.1157, 80.2925, 2.8, 'neighbourhood', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-ROYAPURAM', 'Royapuram', 'Chennai', 'Tamil Nadu', 'IN', '600013', 13.1137, 80.2921, 2.5, 'neighbourhood', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-OMR-CORRIDOR', 'OMR Corridor', 'Chennai', 'Tamil Nadu', 'IN', '600097', 12.9350, 80.2300, 8.5, 'corridor', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-ECR-CORRIDOR', 'ECR Corridor', 'Chennai', 'Tamil Nadu', 'IN', '600041', 12.9800, 80.2590, 7.5, 'corridor', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai'),
  ('CHN-GST-CORRIDOR', 'GST Corridor', 'Chennai', 'Tamil Nadu', 'IN', '600043', 12.9700, 80.1500, 8.0, 'corridor', 'Justapedia', 'https://justapedia.org/wiki/List_of_neighbourhoods_of_Chennai', 'List of neighbourhoods of Chennai')
ON CONFLICT (zone_code) DO UPDATE
SET
  zone_name = EXCLUDED.zone_name,
  city = EXCLUDED.city,
  state = EXCLUDED.state,
  country = EXCLUDED.country,
  pincode = EXCLUDED.pincode,
  center_lat = EXCLUDED.center_lat,
  center_lng = EXCLUDED.center_lng,
  radius_km = EXCLUDED.radius_km,
  zone_level = EXCLUDED.zone_level,
  source_name = EXCLUDED.source_name,
  source_url = EXCLUDED.source_url,
  source_ref = EXCLUDED.source_ref,
  updated_at = NOW();

-- Backfill existing rides with zone ids where missing.
WITH pickup_match AS (
  SELECT
    r.id AS ride_id,
    z.id AS zone_id
  FROM rides r
  JOIN LATERAL (
    SELECT zc.id, zc.zone_code, zc.radius_km,
      (
        6371.0 * acos(
          LEAST(
            1.0,
            GREATEST(
              -1.0,
              cos(radians(r.pickup_lat)) * cos(radians(zc.center_lat)) *
              cos(radians(zc.center_lng) - radians(r.pickup_lng)) +
              sin(radians(r.pickup_lat)) * sin(radians(zc.center_lat))
            )
          )
        )
      ) AS distance_km
    FROM zone_catalog zc
    WHERE zc.is_active = true
      AND zc.city = 'Chennai'
      AND zc.state = 'Tamil Nadu'
      AND zc.country = 'IN'
      AND r.pickup_lat IS NOT NULL
      AND r.pickup_lng IS NOT NULL
    ORDER BY distance_km ASC, zc.radius_km ASC, zc.zone_code ASC
    LIMIT 1
  ) z ON z.distance_km <= z.radius_km
  WHERE r.pickup_zone_id IS NULL
),
drop_match AS (
  SELECT
    r.id AS ride_id,
    z.id AS zone_id
  FROM rides r
  JOIN LATERAL (
    SELECT zc.id, zc.zone_code, zc.radius_km,
      (
        6371.0 * acos(
          LEAST(
            1.0,
            GREATEST(
              -1.0,
              cos(radians(r.dropoff_lat)) * cos(radians(zc.center_lat)) *
              cos(radians(zc.center_lng) - radians(r.dropoff_lng)) +
              sin(radians(r.dropoff_lat)) * sin(radians(zc.center_lat))
            )
          )
        )
      ) AS distance_km
    FROM zone_catalog zc
    WHERE zc.is_active = true
      AND zc.city = 'Chennai'
      AND zc.state = 'Tamil Nadu'
      AND zc.country = 'IN'
      AND r.dropoff_lat IS NOT NULL
      AND r.dropoff_lng IS NOT NULL
    ORDER BY distance_km ASC, zc.radius_km ASC, zc.zone_code ASC
    LIMIT 1
  ) z ON z.distance_km <= z.radius_km
  WHERE r.drop_zone_id IS NULL
)
UPDATE rides r
SET
  pickup_zone_id = COALESCE(pm.zone_id, r.pickup_zone_id),
  drop_zone_id = COALESCE(dm.zone_id, r.drop_zone_id),
  updated_at = NOW()
FROM pickup_match pm
FULL OUTER JOIN drop_match dm ON dm.ride_id = pm.ride_id
WHERE r.id = COALESCE(pm.ride_id, dm.ride_id);

COMMIT;

