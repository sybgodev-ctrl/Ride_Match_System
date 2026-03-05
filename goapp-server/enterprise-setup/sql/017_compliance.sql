-- ============================================================
-- GoApp Enterprise Schema: 017 - Compliance & Regulatory
-- Domain: Compliance (6 tables)
-- ============================================================

CREATE TABLE IF NOT EXISTS regulatory_reports (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_type         VARCHAR(50) NOT NULL,
    jurisdiction        VARCHAR(100) NOT NULL,
    reporting_period    TSTZRANGE NOT NULL,
    data                JSONB NOT NULL,
    status              VARCHAR(20) DEFAULT 'generated',
    submitted_at        TIMESTAMPTZ,
    acknowledged_at     TIMESTAMPTZ,
    document_url        TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS tax_jurisdiction_rules (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    jurisdiction        VARCHAR(100) NOT NULL,
    tax_type            VARCHAR(50) NOT NULL,
    rate                DECIMAL(6,4) NOT NULL,
    applies_to          VARCHAR(30) CHECK (applies_to IN ('rider','driver','platform')),
    conditions          JSONB,
    effective_from      TIMESTAMPTZ NOT NULL,
    effective_until     TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS driver_tax_withholdings (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id           UUID NOT NULL REFERENCES drivers(id),
    tax_type            VARCHAR(50) NOT NULL,
    period_start        DATE NOT NULL,
    period_end          DATE NOT NULL,
    gross_amount        DECIMAL(14,2),
    withholding_rate    DECIMAL(6,4),
    withheld_amount     DECIMAL(12,2),
    remitted            BOOLEAN DEFAULT false,
    remitted_at         TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS data_retention_policies (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    data_category       VARCHAR(100) NOT NULL,
    retention_days      INTEGER NOT NULL,
    jurisdiction        VARCHAR(100),
    deletion_strategy   VARCHAR(30) CHECK (deletion_strategy IN ('hard_delete','anonymize','archive')),
    is_active           BOOLEAN DEFAULT true,
    last_executed_at    TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS data_deletion_requests (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES users(id),
    request_type        VARCHAR(30) NOT NULL CHECK (request_type IN ('gdpr_delete','ccpa_delete','account_delete')),
    status              VARCHAR(20) DEFAULT 'pending'
                        CHECK (status IN ('pending','processing','completed','rejected')),
    data_categories     TEXT[],
    requested_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deadline            TIMESTAMPTZ NOT NULL,
    completed_at        TIMESTAMPTZ,
    processed_by        UUID REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS audit_trails (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_type         VARCHAR(50) NOT NULL,
    entity_id           UUID NOT NULL,
    action              VARCHAR(30) NOT NULL,
    actor_id            UUID REFERENCES users(id),
    actor_type          VARCHAR(20),
    old_values          JSONB,
    new_values          JSONB,
    ip_address          INET,
    user_agent          TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_audit ON audit_trails(entity_type, entity_id, created_at DESC);

-- Compliance & Regulatory: 6 tables total
