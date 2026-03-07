-- ============================================================
-- GoApp Enterprise Schema: 014 - Scheduling / Reservation Service
-- Domain: Scheduling (5 tables)
-- ============================================================

CREATE TABLE IF NOT EXISTS scheduled_rides (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id             UUID NOT NULL REFERENCES rides(id),
    rider_id            UUID NOT NULL REFERENCES riders(id),
    scheduled_pickup_at TIMESTAMPTZ NOT NULL,
    reminder_sent       BOOLEAN DEFAULT false,
    pre_dispatch_at     TIMESTAMPTZ,
    status              VARCHAR(20) DEFAULT 'scheduled'
                        CHECK (status IN ('scheduled','reminder_sent','dispatching','dispatched',
                                          'cancelled','expired')),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_scheduled ON scheduled_rides(scheduled_pickup_at, status);

CREATE TABLE IF NOT EXISTS recurring_ride_templates (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rider_id            UUID NOT NULL REFERENCES riders(id),
    template_name       VARCHAR(200),
    pickup_lat          DECIMAL(10,7) NOT NULL,
    pickup_lng          DECIMAL(10,7) NOT NULL,
    pickup_address      TEXT,
    dropoff_lat         DECIMAL(10,7) NOT NULL,
    dropoff_lng         DECIMAL(10,7) NOT NULL,
    dropoff_address     TEXT,
    vehicle_type_id     UUID REFERENCES vehicle_types(id),
    recurrence_rule     JSONB NOT NULL,
    pickup_time         TIME NOT NULL,
    is_active           BOOLEAN DEFAULT true,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS schedule_dispatch_queue (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scheduled_ride_id   UUID NOT NULL REFERENCES scheduled_rides(id),
    dispatch_at         TIMESTAMPTZ NOT NULL,
    status              VARCHAR(20) DEFAULT 'queued'
                        CHECK (status IN ('queued','dispatching','dispatched','failed','cancelled')),
    attempts            INTEGER DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS schedule_reminders (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scheduled_ride_id   UUID NOT NULL REFERENCES scheduled_rides(id),
    reminder_type       VARCHAR(20) CHECK (reminder_type IN ('30min','15min','5min','custom')),
    channel             VARCHAR(20),
    sent_at             TIMESTAMPTZ,
    status              VARCHAR(20) DEFAULT 'pending'
);

CREATE TABLE IF NOT EXISTS schedule_analytics (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    date                DATE NOT NULL,
    city_region_id      UUID REFERENCES city_regions(id),
    total_scheduled     INTEGER DEFAULT 0,
    converted_to_ride   INTEGER DEFAULT 0,
    cancelled           INTEGER DEFAULT 0,
    no_driver_found     INTEGER DEFAULT 0,
    avg_advance_minutes INTEGER,
    UNIQUE(date, city_region_id)
);

-- Scheduling Service: 5 tables total
