-- ============================================================
-- GoApp Enterprise Schema: 011 - Fraud & Risk System
-- Domain: Fraud & Risk (12 tables)
-- ============================================================

CREATE TABLE IF NOT EXISTS fraud_rules (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rule_name           VARCHAR(200) NOT NULL,
    rule_type           VARCHAR(30) NOT NULL,
    conditions          JSONB NOT NULL,
    action              VARCHAR(30) NOT NULL
                        CHECK (action IN ('flag','block','suspend','alert','manual_review')),
    severity            VARCHAR(10) CHECK (severity IN ('low','medium','high','critical')),
    is_active           BOOLEAN DEFAULT true,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS fraud_flags (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID REFERENCES users(id),
    ride_id             UUID REFERENCES rides(id),
    rule_id             UUID REFERENCES fraud_rules(id),
    flag_type           VARCHAR(50) NOT NULL,
    severity            VARCHAR(10) NOT NULL,
    evidence            JSONB NOT NULL,
    status              VARCHAR(20) DEFAULT 'open'
                        CHECK (status IN ('open','investigating','confirmed','dismissed','resolved')),
    assigned_to         UUID REFERENCES users(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at         TIMESTAMPTZ,
    resolution_notes    TEXT
);
CREATE INDEX IF NOT EXISTS idx_fraud_flags ON fraud_flags(user_id, status);

CREATE TABLE IF NOT EXISTS fraud_detection_logs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rule_id             UUID REFERENCES fraud_rules(id),
    user_id             UUID,
    ride_id             UUID,
    input_data          JSONB,
    result              VARCHAR(20) NOT NULL,
    score               DECIMAL(6,4),
    processing_ms       INTEGER,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS fraud_blacklist (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    identifier_type     VARCHAR(30) NOT NULL
                        CHECK (identifier_type IN ('phone','email','device','ip','card','upi')),
    identifier_value    VARCHAR(500) NOT NULL,
    reason              TEXT NOT NULL,
    added_by            UUID REFERENCES users(id),
    is_active           BOOLEAN DEFAULT true,
    expires_at          TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_blacklist ON fraud_blacklist(identifier_type, identifier_value);

CREATE TABLE IF NOT EXISTS suspicious_activity (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID REFERENCES users(id),
    activity_type       VARCHAR(50) NOT NULL,
    description         TEXT,
    risk_score          DECIMAL(5,2),
    indicators          JSONB,
    auto_action_taken   VARCHAR(50),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS device_fingerprints (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID REFERENCES users(id),
    fingerprint_hash    VARCHAR(128) NOT NULL,
    device_data         JSONB NOT NULL,
    is_trusted          BOOLEAN DEFAULT false,
    is_flagged          BOOLEAN DEFAULT false,
    first_seen_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    seen_count          INTEGER DEFAULT 1
);
CREATE INDEX IF NOT EXISTS idx_fingerprint ON device_fingerprints(fingerprint_hash);

CREATE TABLE IF NOT EXISTS risk_scores (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES users(id),
    overall_score       DECIMAL(5,2) NOT NULL,
    score_components    JSONB NOT NULL,
    risk_level          VARCHAR(10) CHECK (risk_level IN ('low','medium','high','critical')),
    model_version       VARCHAR(50),
    computed_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_risk ON risk_scores(user_id, computed_at DESC);

CREATE TABLE IF NOT EXISTS fraud_gps_spoofing (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id           UUID NOT NULL REFERENCES drivers(id),
    ride_id             UUID REFERENCES rides(id),
    detection_method    VARCHAR(50) NOT NULL,
    evidence            JSONB NOT NULL,
    confidence          DECIMAL(5,2),
    action_taken        VARCHAR(30),
    detected_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS fraud_collusion_detection (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id           UUID REFERENCES drivers(id),
    rider_id            UUID REFERENCES riders(id),
    pattern_type        VARCHAR(50) NOT NULL,
    ride_ids            UUID[] NOT NULL,
    evidence            JSONB NOT NULL,
    confidence          DECIMAL(5,2),
    detected_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS fraud_wallet_abuse (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id           UUID NOT NULL,
    user_id             UUID NOT NULL REFERENCES users(id),
    abuse_type          VARCHAR(50) NOT NULL,
    amount_involved     DECIMAL(12,2),
    evidence            JSONB,
    action_taken        VARCHAR(30),
    detected_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS fraud_investigation_queue (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fraud_flag_id       UUID REFERENCES fraud_flags(id),
    priority            INTEGER NOT NULL,
    assigned_to         UUID REFERENCES users(id),
    status              VARCHAR(20) DEFAULT 'queued',
    sla_deadline        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS fraud_ml_models (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    model_name          VARCHAR(100) NOT NULL,
    model_version       VARCHAR(50) NOT NULL,
    model_type          VARCHAR(50),
    accuracy            DECIMAL(5,4),
    precision_score     DECIMAL(5,4),
    recall_score        DECIMAL(5,4),
    is_active           BOOLEAN DEFAULT false,
    deployed_at         TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Fraud & Risk System: 12 tables total
