-- ============================================================
-- GoApp Enterprise Schema: 015 - Corporate / B2B Accounts
-- Domain: Corporate B2B (6 tables)
-- ============================================================

CREATE TABLE IF NOT EXISTS corporate_accounts (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_name        VARCHAR(300) NOT NULL,
    company_email       VARCHAR(255),
    billing_address     JSONB,
    tax_id              VARCHAR(50),
    account_manager_id  UUID REFERENCES users(id),
    credit_limit        DECIMAL(14,2),
    current_balance     DECIMAL(14,2) DEFAULT 0,
    billing_cycle       VARCHAR(20) DEFAULT 'monthly',
    status              VARCHAR(20) DEFAULT 'active',
    contract_url        TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS corporate_policies (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    corporate_id        UUID NOT NULL REFERENCES corporate_accounts(id),
    policy_name         VARCHAR(200) NOT NULL,
    max_fare_per_ride   DECIMAL(10,2),
    max_rides_per_month INTEGER,
    allowed_vehicle_types UUID[],
    allowed_hours       JSONB,
    allowed_zones       UUID[],
    requires_approval   BOOLEAN DEFAULT false,
    is_active           BOOLEAN DEFAULT true,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS corporate_billing (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    corporate_id        UUID NOT NULL REFERENCES corporate_accounts(id),
    billing_period_start DATE NOT NULL,
    billing_period_end  DATE NOT NULL,
    total_rides         INTEGER,
    total_amount        DECIMAL(14,2),
    tax_amount          DECIMAL(12,2),
    invoice_number      VARCHAR(50) UNIQUE,
    invoice_url         TEXT,
    status              VARCHAR(20) DEFAULT 'pending'
                        CHECK (status IN ('pending','generated','sent','paid','overdue')),
    due_date            DATE,
    paid_at             TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS employee_ride_allocations (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    corporate_id        UUID NOT NULL REFERENCES corporate_accounts(id),
    user_id             UUID NOT NULL REFERENCES users(id),
    policy_id           UUID REFERENCES corporate_policies(id),
    monthly_limit       DECIMAL(10,2),
    used_amount         DECIMAL(10,2) DEFAULT 0,
    rides_used          INTEGER DEFAULT 0,
    period_start        DATE NOT NULL,
    period_end          DATE NOT NULL,
    UNIQUE(corporate_id, user_id, period_start)
);

CREATE TABLE IF NOT EXISTS corporate_invoices (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    corporate_id        UUID NOT NULL REFERENCES corporate_accounts(id),
    billing_id          UUID NOT NULL REFERENCES corporate_billing(id),
    invoice_number      VARCHAR(50) UNIQUE NOT NULL,
    line_items          JSONB NOT NULL,
    subtotal            DECIMAL(14,2),
    tax                 DECIMAL(12,2),
    total               DECIMAL(14,2),
    pdf_url             TEXT,
    generated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS corporate_ride_approvals (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id             UUID NOT NULL REFERENCES rides(id),
    employee_id         UUID NOT NULL REFERENCES users(id),
    corporate_id        UUID NOT NULL REFERENCES corporate_accounts(id),
    approver_id         UUID REFERENCES users(id),
    status              VARCHAR(20) DEFAULT 'pending'
                        CHECK (status IN ('pending','approved','rejected','auto_approved')),
    requested_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    responded_at        TIMESTAMPTZ
);

-- Corporate / B2B: 6 tables total
