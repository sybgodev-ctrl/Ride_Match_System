-- ============================================================
-- GoApp Enterprise Schema: 012 - Promotions & Referrals
-- Domain: Promotions & Referrals (12 tables)
-- ============================================================

CREATE TABLE IF NOT EXISTS promo_campaigns (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_name       VARCHAR(200) NOT NULL,
    description         TEXT,
    campaign_type       VARCHAR(30) NOT NULL
                        CHECK (campaign_type IN ('acquisition','retention','reactivation',
                                                 'seasonal','partnership','loyalty')),
    budget              DECIMAL(14,2),
    spent               DECIMAL(14,2) DEFAULT 0,
    target_audience     JSONB,
    status              VARCHAR(20) DEFAULT 'draft',
    start_date          TIMESTAMPTZ NOT NULL,
    end_date            TIMESTAMPTZ NOT NULL,
    created_by          UUID REFERENCES users(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS promo_codes (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id         UUID REFERENCES promo_campaigns(id),
    code                VARCHAR(50) UNIQUE NOT NULL,
    discount_type       VARCHAR(20) NOT NULL CHECK (discount_type IN ('flat','percentage','cashback')),
    discount_value      DECIMAL(10,2) NOT NULL,
    max_discount        DECIMAL(10,2),
    min_ride_fare       DECIMAL(10,2),
    applicable_vehicle_types UUID[],
    applicable_cities   UUID[],
    is_first_ride_only  BOOLEAN DEFAULT false,
    max_uses_total      INTEGER,
    max_uses_per_user   INTEGER DEFAULT 1,
    current_uses        INTEGER DEFAULT 0,
    is_active           BOOLEAN DEFAULT true,
    valid_from          TIMESTAMPTZ NOT NULL,
    valid_until         TIMESTAMPTZ NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_promo_code ON promo_codes(code);

CREATE TABLE IF NOT EXISTS promo_usage (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    promo_code_id       UUID NOT NULL REFERENCES promo_codes(id),
    user_id             UUID NOT NULL REFERENCES users(id),
    ride_id             UUID REFERENCES rides(id),
    discount_applied    DECIMAL(10,2) NOT NULL,
    used_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_promo_usage ON promo_usage(user_id, promo_code_id);

CREATE TABLE IF NOT EXISTS promo_limits (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    promo_code_id       UUID NOT NULL REFERENCES promo_codes(id),
    limit_type          VARCHAR(30) NOT NULL,
    limit_value         INTEGER NOT NULL,
    current_value       INTEGER DEFAULT 0,
    UNIQUE(promo_code_id, limit_type)
);

CREATE TABLE IF NOT EXISTS promo_rules (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    promo_code_id       UUID NOT NULL REFERENCES promo_codes(id),
    rule_type           VARCHAR(50) NOT NULL,
    rule_conditions     JSONB NOT NULL,
    priority            INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS promo_redemptions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    promo_code_id       UUID NOT NULL REFERENCES promo_codes(id),
    user_id             UUID NOT NULL REFERENCES users(id),
    ride_id             UUID NOT NULL REFERENCES rides(id),
    original_fare       DECIMAL(10,2) NOT NULL,
    discount_amount     DECIMAL(10,2) NOT NULL,
    final_fare          DECIMAL(10,2) NOT NULL,
    redeemed_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS referral_programs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    program_name        VARCHAR(200) NOT NULL,
    referrer_reward     DECIMAL(10,2) NOT NULL,
    referee_reward      DECIMAL(10,2) NOT NULL,
    reward_type         VARCHAR(20) CHECK (reward_type IN ('wallet_credit','promo_code','cashback')),
    conditions          JSONB,
    is_active           BOOLEAN DEFAULT true,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS referral_codes (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES users(id),
    program_id          UUID NOT NULL REFERENCES referral_programs(id),
    code                VARCHAR(20) UNIQUE NOT NULL,
    uses_count          INTEGER DEFAULT 0,
    max_uses            INTEGER,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS referral_tracking (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    referral_code_id    UUID NOT NULL REFERENCES referral_codes(id),
    referrer_id         UUID NOT NULL REFERENCES users(id),
    referee_id          UUID NOT NULL REFERENCES users(id),
    status              VARCHAR(20) DEFAULT 'pending'
                        CHECK (status IN ('pending','signup_complete','first_ride','reward_issued','expired')),
    referrer_rewarded   BOOLEAN DEFAULT false,
    referee_rewarded    BOOLEAN DEFAULT false,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at        TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS referral_payouts (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tracking_id         UUID NOT NULL REFERENCES referral_tracking(id),
    user_id             UUID NOT NULL REFERENCES users(id),
    amount              DECIMAL(10,2) NOT NULL,
    payout_type         VARCHAR(20) NOT NULL,
    status              VARCHAR(20) DEFAULT 'pending',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS promo_analytics (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id         UUID REFERENCES promo_campaigns(id),
    promo_code_id       UUID REFERENCES promo_codes(id),
    analytics_date      DATE NOT NULL,
    impressions         INTEGER DEFAULT 0,
    redemptions         INTEGER DEFAULT 0,
    total_discount      DECIMAL(12,2) DEFAULT 0,
    incremental_rides   INTEGER DEFAULT 0,
    roi_estimate        DECIMAL(8,4)
);

CREATE TABLE IF NOT EXISTS promo_ab_tests (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    test_name           VARCHAR(200),
    variant_a_code_id   UUID REFERENCES promo_codes(id),
    variant_b_code_id   UUID REFERENCES promo_codes(id),
    target_metric       VARCHAR(50),
    status              VARCHAR(20) DEFAULT 'running',
    winner              VARCHAR(10),
    results             JSONB,
    started_at          TIMESTAMPTZ,
    ended_at            TIMESTAMPTZ
);

-- Promotions & Referrals: 12 tables total
