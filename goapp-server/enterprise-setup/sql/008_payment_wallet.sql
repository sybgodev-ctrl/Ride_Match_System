-- ============================================================
-- GoApp Enterprise Schema: 008 - Payment & Wallet Service
-- Domain: Payment Service (20 tables)
-- Note: PCI-DSS isolated database recommended in production
-- ============================================================

CREATE TABLE IF NOT EXISTS payment_methods (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES users(id),
    method_type         VARCHAR(30) NOT NULL
                        CHECK (method_type IN ('card','upi','netbanking','wallet','cash','corporate')),
    provider            VARCHAR(50),
    token               TEXT,
    last_four           VARCHAR(4),
    card_brand          VARCHAR(20),
    upi_id              VARCHAR(100),
    is_default          BOOLEAN DEFAULT false,
    is_verified         BOOLEAN DEFAULT false,
    metadata            JSONB,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_payment_methods ON payment_methods(user_id);

CREATE TABLE IF NOT EXISTS payments (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id             UUID NOT NULL REFERENCES rides(id),
    rider_id            UUID NOT NULL REFERENCES riders(id),
    payment_method_id   UUID REFERENCES payment_methods(id),
    amount              DECIMAL(10,2) NOT NULL,
    currency            VARCHAR(3) DEFAULT 'INR',
    status              VARCHAR(20) NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending','authorized','captured','completed',
                                          'failed','refunded','partially_refunded','disputed')),
    gateway             VARCHAR(50),
    gateway_ref_id      VARCHAR(200),
    idempotency_key     VARCHAR(200) UNIQUE NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_payments_ride ON payments(ride_id);
CREATE INDEX IF NOT EXISTS idx_payments_status ON payments(status);

CREATE TABLE IF NOT EXISTS payment_transactions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id          UUID NOT NULL REFERENCES payments(id),
    transaction_type    VARCHAR(30) NOT NULL
                        CHECK (transaction_type IN ('authorize','capture','void','refund',
                                                    'chargeback','settlement')),
    amount              DECIMAL(10,2) NOT NULL,
    status              VARCHAR(20) NOT NULL,
    gateway             VARCHAR(50),
    gateway_txn_id      VARCHAR(200),
    gateway_response    JSONB,
    error_code          VARCHAR(50),
    error_message       TEXT,
    idempotency_key     VARCHAR(200) UNIQUE NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_pay_txn ON payment_transactions(payment_id);

CREATE TABLE IF NOT EXISTS payment_refunds (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id          UUID NOT NULL REFERENCES payments(id),
    ride_id             UUID NOT NULL,
    refund_amount       DECIMAL(10,2) NOT NULL,
    reason              TEXT NOT NULL,
    initiated_by        UUID REFERENCES users(id),
    status              VARCHAR(20) DEFAULT 'pending'
                        CHECK (status IN ('pending','processing','completed','failed')),
    gateway_refund_id   VARCHAR(200),
    idempotency_key     VARCHAR(200) UNIQUE NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    processed_at        TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS payment_disputes (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id          UUID NOT NULL REFERENCES payments(id),
    dispute_type        VARCHAR(30) NOT NULL,
    amount              DECIMAL(10,2) NOT NULL,
    reason              TEXT,
    evidence            JSONB,
    status              VARCHAR(20) DEFAULT 'open',
    gateway_dispute_id  VARCHAR(200),
    deadline            TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at         TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS payment_webhooks (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gateway             VARCHAR(50) NOT NULL,
    event_type          VARCHAR(100) NOT NULL,
    payload             JSONB NOT NULL,
    signature           TEXT,
    is_verified         BOOLEAN DEFAULT false,
    is_processed        BOOLEAN DEFAULT false,
    process_attempts    INTEGER DEFAULT 0,
    error_message       TEXT,
    received_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    processed_at        TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_webhooks ON payment_webhooks(is_processed, received_at);

CREATE TABLE IF NOT EXISTS payment_failures (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id          UUID NOT NULL REFERENCES payments(id),
    failure_code        VARCHAR(50) NOT NULL,
    failure_message     TEXT,
    gateway_error       JSONB,
    retry_eligible      BOOLEAN DEFAULT true,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS payment_retries (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id          UUID NOT NULL REFERENCES payments(id),
    attempt_number      INTEGER NOT NULL,
    status              VARCHAR(20) NOT NULL,
    error_code          VARCHAR(50),
    next_retry_at       TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS idempotency_keys (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key                 VARCHAR(200) UNIQUE NOT NULL,
    request_hash        VARCHAR(64) NOT NULL,
    response_code       INTEGER,
    response_body       JSONB,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at          TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_idemp ON idempotency_keys(key);

-- ──────────────────────────────────────────────────────
-- Wallet Tables
-- ──────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS wallets (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL UNIQUE REFERENCES users(id),
    balance             DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (balance >= 0),
    promo_balance       DECIMAL(12,2) NOT NULL DEFAULT 0,
    currency            VARCHAR(3) DEFAULT 'INR',
    status              VARCHAR(20) DEFAULT 'active'
                        CHECK (status IN ('active','frozen','suspended','closed')),
    version             INTEGER NOT NULL DEFAULT 1,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS wallet_transactions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id           UUID NOT NULL REFERENCES wallets(id),
    transaction_type    VARCHAR(30) NOT NULL
                        CHECK (transaction_type IN ('topup','ride_payment','refund','promo_credit',
                                                    'cashback','withdrawal','adjustment','hold','release')),
    amount              DECIMAL(12,2) NOT NULL,
    balance_before      DECIMAL(12,2) NOT NULL,
    balance_after       DECIMAL(12,2) NOT NULL,
    reference_type      VARCHAR(30),
    reference_id        UUID,
    description         TEXT,
    idempotency_key     VARCHAR(200) UNIQUE NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_wallet_txn ON wallet_transactions(wallet_id, created_at DESC);

CREATE TABLE IF NOT EXISTS wallet_topups (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id           UUID NOT NULL REFERENCES wallets(id),
    amount              DECIMAL(12,2) NOT NULL,
    payment_method_id   UUID REFERENCES payment_methods(id),
    gateway_ref         VARCHAR(200),
    status              VARCHAR(20) DEFAULT 'pending',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS wallet_refunds (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id           UUID NOT NULL REFERENCES wallets(id),
    ride_id             UUID,
    amount              DECIMAL(12,2) NOT NULL,
    reason              TEXT,
    status              VARCHAR(20) DEFAULT 'pending',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS wallet_holds (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id           UUID NOT NULL REFERENCES wallets(id),
    ride_id             UUID NOT NULL,
    hold_amount         DECIMAL(12,2) NOT NULL,
    status              VARCHAR(20) DEFAULT 'held'
                        CHECK (status IN ('held','captured','released','expired')),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at          TIMESTAMPTZ NOT NULL,
    resolved_at         TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS wallet_limits (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id           UUID NOT NULL REFERENCES wallets(id),
    limit_type          VARCHAR(30) NOT NULL,
    max_amount          DECIMAL(12,2) NOT NULL,
    current_usage       DECIMAL(12,2) DEFAULT 0,
    reset_at            TIMESTAMPTZ,
    UNIQUE(wallet_id, limit_type)
);

CREATE TABLE IF NOT EXISTS wallet_audit_logs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id           UUID NOT NULL REFERENCES wallets(id),
    action              VARCHAR(50) NOT NULL,
    performed_by        UUID REFERENCES users(id),
    old_value           JSONB,
    new_value           JSONB,
    reason              TEXT,
    ip_address          INET,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS wallet_expiry_rules (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id           UUID NOT NULL REFERENCES wallets(id),
    promo_credit_id     UUID,
    amount              DECIMAL(12,2) NOT NULL,
    expires_at          TIMESTAMPTZ NOT NULL,
    is_expired          BOOLEAN DEFAULT false,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Payment + Wallet Service: 20 tables total (9 payment + 8 wallet + 3 shared)
