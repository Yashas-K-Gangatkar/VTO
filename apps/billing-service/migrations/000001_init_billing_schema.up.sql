-- ============================================================
-- Migration 000001: Initialize billing schema
-- ============================================================
-- Per DR-026: $0.15/try-on + $2K/mo minimum commit + $25/SKU digitization
-- Per DR-025: billing occurs on tryon.viewed event

CREATE TABLE billing.pricing_tiers (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    retailer_id                 UUID REFERENCES public.retailers(id),
    name                        VARCHAR(100) NOT NULL,
    min_volume                  INTEGER NOT NULL DEFAULT 0,
    max_volume                  INTEGER,
    price_per_tryon_cents       INTEGER NOT NULL,
    minimum_monthly_commit_cents INTEGER NOT NULL DEFAULT 0,
    effective_from              TIMESTAMPTZ NOT NULL,
    effective_to                TIMESTAMPTZ,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_pricing_tiers_retailer ON billing.pricing_tiers(retailer_id, effective_from DESC);

ALTER TABLE billing.pricing_tiers ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation_pricing_tiers ON billing.pricing_tiers
    USING (retailer_id = current_setting('app.retailer_id', true)::UUID OR retailer_id IS NULL);

CREATE TABLE billing.usage_records (
    id                  BIGSERIAL PRIMARY KEY,
    retailer_id         UUID NOT NULL REFERENCES public.retailers(id),
    tryon_id            UUID NOT NULL,
    event_type          VARCHAR(50) NOT NULL,
    billed_amount_cents INTEGER NOT NULL,
    pricing_tier_id     UUID NOT NULL REFERENCES billing.pricing_tiers(id),
    recorded_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    invoice_id          UUID
);

CREATE INDEX idx_usage_retailer_date ON billing.usage_records(retailer_id, recorded_at DESC);
CREATE INDEX idx_usage_invoice ON billing.usage_records(invoice_id) WHERE invoice_id IS NOT NULL;

ALTER TABLE billing.usage_records ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation_usage_records ON billing.usage_records
    USING (retailer_id = current_setting('app.retailer_id', true)::UUID);

CREATE TABLE billing.invoices (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    retailer_id     UUID NOT NULL REFERENCES public.retailers(id),
    stripe_invoice_id VARCHAR(100) UNIQUE,
    period_start    TIMESTAMPTZ NOT NULL,
    period_end      TIMESTAMPTZ NOT NULL,
    subtotal_cents  INTEGER NOT NULL,
    tax_cents       INTEGER NOT NULL DEFAULT 0,
    total_cents     INTEGER NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'open',
    due_date        TIMESTAMPTZ NOT NULL,
    paid_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_invoices_retailer ON billing.invoices(retailer_id, period_start DESC);
CREATE INDEX idx_invoices_stripe ON billing.invoices(stripe_invoice_id);

ALTER TABLE billing.invoices ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation_invoices ON billing.invoices
    USING (retailer_id = current_setting('app.retailer_id', true)::UUID);
