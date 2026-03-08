-- ============================================================
-- GoApp Enterprise Schema: 019 - Event System & Schema Registry
-- Domain: Event System (4 tables)
-- ============================================================

CREATE TABLE IF NOT EXISTS event_schemas (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type          VARCHAR(100) NOT NULL,
    version             INTEGER NOT NULL,
    schema_definition   JSONB NOT NULL,
    is_latest           BOOLEAN DEFAULT true,
    backward_compatible BOOLEAN DEFAULT true,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(event_type, version)
);

CREATE TABLE IF NOT EXISTS schema_versions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    schema_id           UUID NOT NULL REFERENCES event_schemas(id),
    change_description  TEXT,
    migration_script    TEXT,
    breaking_change     BOOLEAN DEFAULT false,
    deployed_at         TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS event_publish_logs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type          VARCHAR(100) NOT NULL,
    event_id            UUID NOT NULL,
    topic               VARCHAR(200) NOT NULL,
    partition_key       VARCHAR(200),
    payload_size_bytes  INTEGER,
    published_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    acknowledged        BOOLEAN DEFAULT false
);

CREATE TABLE IF NOT EXISTS event_consumer_offsets (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    consumer_group      VARCHAR(100) NOT NULL,
    topic               VARCHAR(200) NOT NULL,
    partition_id        INTEGER NOT NULL,
    current_offset      BIGINT NOT NULL,
    committed_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(consumer_group, topic, partition_id)
);

-- Event System & Schema Registry: 4 tables total
