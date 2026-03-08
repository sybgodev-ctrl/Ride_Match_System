-- ============================================================
-- GoApp Enterprise Schema: 013 - Safety / SOS Service
-- Domain: Safety & SOS (8 tables)
-- ============================================================

CREATE TABLE IF NOT EXISTS emergency_contacts (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES users(id),
    contact_name        VARCHAR(200) NOT NULL,
    phone_number        VARCHAR(20) NOT NULL,
    relationship        VARCHAR(50),
    is_primary          BOOLEAN DEFAULT false,
    auto_share_rides    BOOLEAN DEFAULT false,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_emergency ON emergency_contacts(user_id);

CREATE TABLE IF NOT EXISTS sos_triggers (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id             UUID NOT NULL REFERENCES rides(id),
    triggered_by        UUID NOT NULL REFERENCES users(id),
    trigger_type        VARCHAR(30) NOT NULL
                        CHECK (trigger_type IN ('manual','crash_detect','long_stop','route_deviation','shake')),
    location            GEOMETRY(Point, 4326),
    status              VARCHAR(20) DEFAULT 'triggered'
                        CHECK (status IN ('triggered','acknowledged','responding','resolved','false_alarm')),
    auto_actions        JSONB,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at         TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS sos_response_logs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sos_id              UUID NOT NULL REFERENCES sos_triggers(id),
    responder_type      VARCHAR(30) NOT NULL
                        CHECK (responder_type IN ('safety_team','police','ambulance','emergency_contact','system')),
    responder_id        UUID,
    action_taken        TEXT NOT NULL,
    response_time_sec   INTEGER,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS safety_check_ins (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id             UUID NOT NULL REFERENCES rides(id),
    user_id             UUID NOT NULL REFERENCES users(id),
    check_in_type       VARCHAR(30) CHECK (check_in_type IN ('auto_prompt','manual','timer_based')),
    response            VARCHAR(20) CHECK (response IN ('safe','unsafe','no_response')),
    prompted_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    responded_at        TIMESTAMPTZ,
    escalated           BOOLEAN DEFAULT false
);

CREATE TABLE IF NOT EXISTS ride_audio_recordings (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id             UUID NOT NULL REFERENCES rides(id),
    recording_url       TEXT NOT NULL,
    duration_seconds    INTEGER,
    started_at          TIMESTAMPTZ NOT NULL,
    ended_at            TIMESTAMPTZ,
    is_encrypted        BOOLEAN DEFAULT true,
    retention_until     TIMESTAMPTZ NOT NULL,
    accessed_by         UUID[],
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS trusted_contacts_shares (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id             UUID NOT NULL REFERENCES rides(id),
    user_id             UUID NOT NULL REFERENCES users(id),
    contact_id          UUID NOT NULL REFERENCES emergency_contacts(id),
    share_type          VARCHAR(20) CHECK (share_type IN ('auto','manual')),
    share_url           TEXT NOT NULL,
    shared_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at          TIMESTAMPTZ NOT NULL,
    viewed_at           TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS safety_incidents (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id             UUID REFERENCES rides(id),
    reported_by         UUID NOT NULL REFERENCES users(id),
    incident_type       VARCHAR(50) NOT NULL,
    severity            VARCHAR(10) NOT NULL,
    description         TEXT NOT NULL,
    evidence_urls       TEXT[],
    location            GEOMETRY(Point, 4326),
    status              VARCHAR(20) DEFAULT 'reported',
    assigned_to         UUID REFERENCES users(id),
    resolution          TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at         TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS safety_scores (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES users(id),
    user_type           VARCHAR(10) NOT NULL,
    safety_score        DECIMAL(5,2) NOT NULL,
    score_factors       JSONB NOT NULL,
    incidents_count     INTEGER DEFAULT 0,
    sos_count           INTEGER DEFAULT 0,
    computed_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Safety / SOS Service: 8 tables total
