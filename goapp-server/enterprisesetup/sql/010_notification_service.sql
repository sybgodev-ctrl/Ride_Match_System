-- ============================================================
-- GoApp Enterprise Schema: 010 - Notification Service
-- Domain: Notification Service (8 tables)
-- ============================================================

CREATE TABLE IF NOT EXISTS notification_templates (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_key        VARCHAR(100) UNIQUE NOT NULL,
    channel             VARCHAR(20) NOT NULL CHECK (channel IN ('push','sms','email','in_app','whatsapp')),
    title_template      TEXT,
    body_template       TEXT NOT NULL,
    variables           TEXT[],
    language            VARCHAR(10) DEFAULT 'en',
    is_active           BOOLEAN DEFAULT true,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS notifications (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES users(id),
    template_id         UUID REFERENCES notification_templates(id),
    channel             VARCHAR(20) NOT NULL,
    title               VARCHAR(200),
    body                TEXT NOT NULL,
    data_payload        JSONB,
    priority            VARCHAR(10) DEFAULT 'normal' CHECK (priority IN ('low','normal','high','critical')),
    status              VARCHAR(20) DEFAULT 'pending'
                        CHECK (status IN ('pending','sent','delivered','read','failed','cancelled')),
    reference_type      VARCHAR(30),
    reference_id        UUID,
    sent_at             TIMESTAMPTZ,
    delivered_at        TIMESTAMPTZ,
    read_at             TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_notif_user ON notifications(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS notification_logs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    notification_id     UUID NOT NULL REFERENCES notifications(id),
    event               VARCHAR(30) NOT NULL,
    provider_response   JSONB,
    error_message       TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS push_tokens (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES users(id),
    device_id           UUID REFERENCES user_devices(id),
    platform            VARCHAR(10) NOT NULL CHECK (platform IN ('ios','android','web')),
    token               TEXT NOT NULL,
    is_active           BOOLEAN DEFAULT true,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_push_tokens ON push_tokens(user_id);

CREATE TABLE IF NOT EXISTS sms_logs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_number        VARCHAR(20) NOT NULL,
    message             TEXT NOT NULL,
    provider            VARCHAR(50),
    provider_msg_id     VARCHAR(200),
    status              VARCHAR(20),
    cost                DECIMAL(8,4),
    sent_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS email_logs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    to_email            VARCHAR(255) NOT NULL,
    subject             VARCHAR(500) NOT NULL,
    template_id         UUID REFERENCES notification_templates(id),
    provider            VARCHAR(50),
    provider_msg_id     VARCHAR(200),
    status              VARCHAR(20),
    opened_at           TIMESTAMPTZ,
    clicked_at          TIMESTAMPTZ,
    sent_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS notification_preferences (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES users(id),
    notification_type   VARCHAR(50) NOT NULL,
    push_enabled        BOOLEAN DEFAULT true,
    sms_enabled         BOOLEAN DEFAULT true,
    email_enabled       BOOLEAN DEFAULT true,
    quiet_hours_start   TIME,
    quiet_hours_end     TIME,
    UNIQUE(user_id, notification_type)
);

CREATE TABLE IF NOT EXISTS in_app_messages (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES users(id),
    message_type        VARCHAR(30),
    title               VARCHAR(200),
    body                TEXT,
    action_url          TEXT,
    image_url           TEXT,
    is_read             BOOLEAN DEFAULT false,
    expires_at          TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Notification Service: 8 tables total
