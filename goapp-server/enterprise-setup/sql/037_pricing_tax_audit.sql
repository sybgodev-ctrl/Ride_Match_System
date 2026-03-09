-- ============================================================
-- 037_pricing_tax_audit.sql
-- Adds admin-configurable platform commission override and GST audit ledger
-- ============================================================

CREATE TABLE IF NOT EXISTS pricing_tax_config (
  id          INTEGER PRIMARY KEY CHECK (id = 1),
  gst_pct     NUMERIC(5,2) NOT NULL DEFAULT 5.00,
  platform_commission_pct NUMERIC(6,4),
  updated_by  TEXT,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE pricing_tax_config
  ADD COLUMN IF NOT EXISTS platform_commission_pct NUMERIC(6,4);

INSERT INTO pricing_tax_config (id, gst_pct)
VALUES (1, 5.00)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS pricing_tax_transactions (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  old_gst_pct   NUMERIC(5,2),
  new_gst_pct   NUMERIC(5,2),
  old_platform_commission_pct NUMERIC(6,4),
  new_platform_commission_pct NUMERIC(6,4),
  action        VARCHAR(30) NOT NULL DEFAULT 'UPDATE_TAX_CONFIG',
  changed_by    TEXT,
  request_id    TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pricing_tax_tx_created_at
  ON pricing_tax_transactions(created_at DESC);
