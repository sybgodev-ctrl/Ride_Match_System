-- ============================================================
-- GoApp Enterprise Schema: 016 - Support & Customer Service
-- Domain: Support (8 tables)
-- ============================================================

CREATE TABLE IF NOT EXISTS support_categories (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name                VARCHAR(200) NOT NULL,
    parent_id           UUID REFERENCES support_categories(id),
    icon                VARCHAR(50),
    sort_order          INTEGER DEFAULT 0,
    is_active           BOOLEAN DEFAULT true
);

CREATE TABLE IF NOT EXISTS support_tickets (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_number       VARCHAR(20) UNIQUE NOT NULL,
    user_id             UUID NOT NULL REFERENCES users(id),
    ride_id             UUID REFERENCES rides(id),
    category_id         UUID REFERENCES support_categories(id),
    subject             VARCHAR(500) NOT NULL,
    description         TEXT NOT NULL,
    priority            VARCHAR(10) DEFAULT 'medium'
                        CHECK (priority IN ('low','medium','high','urgent')),
    status              VARCHAR(20) DEFAULT 'open'
                        CHECK (status IN ('open','assigned','in_progress','waiting_user',
                                          'resolved','closed','reopened')),
    assigned_to         UUID REFERENCES users(id),
    sla_deadline        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at         TIMESTAMPTZ,
    closed_at           TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_tickets ON support_tickets(user_id, status);

CREATE TABLE IF NOT EXISTS support_ticket_messages (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id           UUID NOT NULL REFERENCES support_tickets(id),
    sender_id           UUID NOT NULL REFERENCES users(id),
    sender_type         VARCHAR(20) CHECK (sender_type IN ('user','agent','system','bot')),
    message             TEXT NOT NULL,
    attachments         TEXT[],
    is_internal         BOOLEAN DEFAULT false,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS support_agents (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL UNIQUE REFERENCES users(id),
    agent_name          VARCHAR(200),
    team                VARCHAR(100),
    skills              TEXT[],
    max_concurrent      INTEGER DEFAULT 5,
    current_load        INTEGER DEFAULT 0,
    is_available        BOOLEAN DEFAULT true,
    shift_start         TIME,
    shift_end           TIME
);

CREATE TABLE IF NOT EXISTS ticket_status_history (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id           UUID NOT NULL REFERENCES support_tickets(id),
    old_status          VARCHAR(20),
    new_status          VARCHAR(20) NOT NULL,
    changed_by          UUID REFERENCES users(id),
    reason              TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ticket_escalations (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id           UUID NOT NULL REFERENCES support_tickets(id),
    escalated_from      UUID REFERENCES users(id),
    escalated_to        UUID REFERENCES users(id),
    escalation_level    INTEGER NOT NULL,
    reason              TEXT NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS support_csat (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id           UUID NOT NULL REFERENCES support_tickets(id),
    user_id             UUID NOT NULL REFERENCES users(id),
    rating              INTEGER CHECK (rating >= 1 AND rating <= 5),
    feedback            TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS support_faq (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category_id         UUID REFERENCES support_categories(id),
    question            TEXT NOT NULL,
    answer              TEXT NOT NULL,
    language            VARCHAR(10) DEFAULT 'en',
    view_count          INTEGER DEFAULT 0,
    helpful_count       INTEGER DEFAULT 0,
    is_active           BOOLEAN DEFAULT true,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Support & Customer Service: 8 tables total
