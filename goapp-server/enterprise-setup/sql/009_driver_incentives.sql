-- ============================================================
-- GoApp Enterprise Schema: 009 - Driver Incentives
-- Domain: Driver Incentives (12 tables)
-- ============================================================

CREATE TABLE IF NOT EXISTS driver_incentives (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name                VARCHAR(200) NOT NULL,
    description         TEXT,
    incentive_type      VARCHAR(30) NOT NULL
                        CHECK (incentive_type IN ('trip_count','earnings_guarantee','streak',
                                                  'peak_hour','area_bonus','referral','quest')),
    city_region_id      UUID REFERENCES city_regions(id),
    vehicle_type_id     UUID REFERENCES vehicle_types(id),
    rules               JSONB NOT NULL,
    budget_total        DECIMAL(12,2),
    budget_spent        DECIMAL(12,2) DEFAULT 0,
    status              VARCHAR(20) DEFAULT 'draft'
                        CHECK (status IN ('draft','active','paused','completed','expired')),
    start_date          TIMESTAMPTZ NOT NULL,
    end_date            TIMESTAMPTZ NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS driver_bonus_rules (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    incentive_id        UUID NOT NULL REFERENCES driver_incentives(id),
    tier                INTEGER NOT NULL,
    target_value        INTEGER NOT NULL,
    bonus_amount        DECIMAL(10,2) NOT NULL,
    bonus_type          VARCHAR(20) CHECK (bonus_type IN ('flat','percentage','per_trip')),
    conditions          JSONB
);

CREATE TABLE IF NOT EXISTS driver_bonus_progress (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id           UUID NOT NULL REFERENCES drivers(id),
    incentive_id        UUID NOT NULL REFERENCES driver_incentives(id),
    current_value       INTEGER DEFAULT 0,
    target_value        INTEGER NOT NULL,
    bonus_earned        DECIMAL(10,2) DEFAULT 0,
    status              VARCHAR(20) DEFAULT 'in_progress'
                        CHECK (status IN ('in_progress','achieved','failed','expired')),
    period_start        TIMESTAMPTZ NOT NULL,
    period_end          TIMESTAMPTZ NOT NULL,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(driver_id, incentive_id, period_start)
);

CREATE TABLE IF NOT EXISTS driver_daily_targets (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id           UUID NOT NULL REFERENCES drivers(id),
    target_date         DATE NOT NULL,
    target_rides        INTEGER,
    completed_rides     INTEGER DEFAULT 0,
    target_hours        DECIMAL(4,1),
    online_hours        DECIMAL(4,1) DEFAULT 0,
    target_earnings     DECIMAL(10,2),
    actual_earnings     DECIMAL(10,2) DEFAULT 0,
    bonus_earned        DECIMAL(10,2) DEFAULT 0,
    UNIQUE(driver_id, target_date)
);

CREATE TABLE IF NOT EXISTS driver_weekly_targets (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id           UUID NOT NULL REFERENCES drivers(id),
    week_start          DATE NOT NULL,
    week_end            DATE NOT NULL,
    target_rides        INTEGER,
    completed_rides     INTEGER DEFAULT 0,
    target_earnings     DECIMAL(12,2),
    actual_earnings     DECIMAL(12,2) DEFAULT 0,
    acceptance_rate     DECIMAL(5,2),
    cancellation_rate   DECIMAL(5,2),
    bonus_earned        DECIMAL(10,2) DEFAULT 0,
    UNIQUE(driver_id, week_start)
);

CREATE TABLE IF NOT EXISTS driver_streaks (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id           UUID NOT NULL REFERENCES drivers(id),
    streak_type         VARCHAR(30) NOT NULL,
    current_count       INTEGER DEFAULT 0,
    target_count        INTEGER NOT NULL,
    bonus_per_completion DECIMAL(10,2),
    started_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at          TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS driver_payouts (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id           UUID NOT NULL REFERENCES drivers(id),
    payout_type         VARCHAR(30) NOT NULL
                        CHECK (payout_type IN ('weekly','instant','bonus','adjustment')),
    amount              DECIMAL(12,2) NOT NULL,
    breakdown           JSONB NOT NULL,
    bank_account_id     UUID REFERENCES driver_bank_accounts(id),
    status              VARCHAR(20) DEFAULT 'pending'
                        CHECK (status IN ('pending','processing','completed','failed','reversed')),
    gateway_ref         VARCHAR(200),
    payout_date         DATE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at        TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_payouts ON driver_payouts(driver_id, created_at DESC);

CREATE TABLE IF NOT EXISTS driver_commissions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id           UUID NOT NULL REFERENCES drivers(id),
    ride_id             UUID NOT NULL REFERENCES rides(id),
    ride_fare           DECIMAL(10,2) NOT NULL,
    commission_rate     DECIMAL(5,4) NOT NULL,
    commission_amount   DECIMAL(10,2) NOT NULL,
    driver_earnings     DECIMAL(10,2) NOT NULL,
    incentive_bonus     DECIMAL(10,2) DEFAULT 0,
    total_driver_pay    DECIMAL(10,2) NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_commission ON driver_commissions(driver_id, created_at DESC);

CREATE TABLE IF NOT EXISTS driver_tax_records (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id           UUID NOT NULL REFERENCES drivers(id),
    tax_year            INTEGER NOT NULL,
    total_earnings      DECIMAL(14,2),
    total_commission    DECIMAL(14,2),
    total_incentives    DECIMAL(14,2),
    tds_deducted        DECIMAL(12,2),
    gst_collected       DECIMAL(12,2),
    tax_document_url    TEXT,
    generated_at        TIMESTAMPTZ,
    UNIQUE(driver_id, tax_year)
);

CREATE TABLE IF NOT EXISTS driver_earnings_summary (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id           UUID NOT NULL REFERENCES drivers(id),
    summary_date        DATE NOT NULL,
    total_rides         INTEGER DEFAULT 0,
    gross_earnings      DECIMAL(12,2) DEFAULT 0,
    commission_deducted DECIMAL(12,2) DEFAULT 0,
    incentive_earned    DECIMAL(12,2) DEFAULT 0,
    tips_received       DECIMAL(12,2) DEFAULT 0,
    tolls_reimbursed    DECIMAL(12,2) DEFAULT 0,
    net_earnings        DECIMAL(12,2) DEFAULT 0,
    online_hours        DECIMAL(5,2) DEFAULT 0,
    earnings_per_hour   DECIMAL(8,2),
    UNIQUE(driver_id, summary_date)
);

CREATE TABLE IF NOT EXISTS driver_heat_map_nudges (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id           UUID NOT NULL REFERENCES drivers(id),
    h3_index            VARCHAR(20) NOT NULL,
    nudge_type          VARCHAR(30) CHECK (nudge_type IN ('high_demand','surge','bonus_zone','event')),
    message             TEXT,
    estimated_earnings  DECIMAL(10,2),
    sent_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at          TIMESTAMPTZ,
    driver_responded    BOOLEAN DEFAULT false
);

CREATE TABLE IF NOT EXISTS area_incentive_zones (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    zone_name           VARCHAR(200),
    h3_indices          TEXT[] NOT NULL,
    bonus_multiplier    DECIMAL(4,2) DEFAULT 1.0,
    bonus_flat          DECIMAL(10,2) DEFAULT 0,
    effective_from      TIMESTAMPTZ NOT NULL,
    effective_until     TIMESTAMPTZ NOT NULL,
    is_active           BOOLEAN DEFAULT true
);

-- Driver Incentives: 12 tables total
