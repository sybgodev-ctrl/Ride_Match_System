-- ============================================================
-- GoApp Enterprise Schema: 018 - Saga Orchestration
-- Domain: Saga / Distributed Transactions (4 tables)
-- ============================================================

CREATE TABLE IF NOT EXISTS saga_instances (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    saga_type           VARCHAR(50) NOT NULL
                        CHECK (saga_type IN ('ride_lifecycle','payment_flow','refund_flow',
                                             'driver_payout','scheduled_ride')),
    correlation_id      UUID NOT NULL,
    current_step        VARCHAR(50) NOT NULL,
    status              VARCHAR(20) NOT NULL DEFAULT 'running'
                        CHECK (status IN ('running','compensating','completed','failed','timed_out')),
    state_data          JSONB NOT NULL,
    started_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at        TIMESTAMPTZ,
    timeout_at          TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_saga ON saga_instances(saga_type, status);
CREATE INDEX IF NOT EXISTS idx_saga_corr ON saga_instances(correlation_id);

CREATE TABLE IF NOT EXISTS saga_step_logs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    saga_id             UUID NOT NULL REFERENCES saga_instances(id),
    step_name           VARCHAR(50) NOT NULL,
    step_order          INTEGER NOT NULL,
    action              VARCHAR(20) NOT NULL CHECK (action IN ('execute','compensate')),
    status              VARCHAR(20) NOT NULL
                        CHECK (status IN ('pending','running','completed','failed','compensated')),
    input_data          JSONB,
    output_data         JSONB,
    error_message       TEXT,
    started_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at        TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_saga_steps ON saga_step_logs(saga_id, step_order);

CREATE TABLE IF NOT EXISTS saga_compensations (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    saga_id             UUID NOT NULL REFERENCES saga_instances(id),
    step_name           VARCHAR(50) NOT NULL,
    compensation_action VARCHAR(100) NOT NULL,
    status              VARCHAR(20) NOT NULL DEFAULT 'pending',
    attempts            INTEGER DEFAULT 0,
    max_attempts        INTEGER DEFAULT 3,
    error_log           JSONB,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    executed_at         TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS dead_letter_events (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    original_topic      VARCHAR(200) NOT NULL,
    event_key           VARCHAR(200),
    event_payload       JSONB NOT NULL,
    error_message       TEXT NOT NULL,
    retry_count         INTEGER DEFAULT 0,
    max_retries         INTEGER DEFAULT 5,
    status              VARCHAR(20) DEFAULT 'pending'
                        CHECK (status IN ('pending','retrying','resolved','abandoned')),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    next_retry_at       TIMESTAMPTZ,
    resolved_at         TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_dle ON dead_letter_events(status, next_retry_at);

-- Saga Orchestration: 4 tables total
