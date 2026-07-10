-- Migration 000002: Add QR codes and attribution tables
-- Per DR-087: QR codes on physical garment tags
-- Per DR-089: Attribution chains QR scan → try-on → purchase

CREATE TABLE tryon.qr_codes (
    id              VARCHAR(100) PRIMARY KEY,
    retailer_id     UUID NOT NULL REFERENCES public.retailers(id),
    sku             VARCHAR(200) NOT NULL,
    payload         TEXT NOT NULL,
    s3_key          VARCHAR(500) NOT NULL,
    issued_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at      TIMESTAMPTZ NOT NULL,
    revoked_at      TIMESTAMPTZ,
    CONSTRAINT chk_qr_id_format CHECK (id ~ '^qr_[0-9a-f-]+$')
);

CREATE INDEX idx_qr_codes_retailer_sku ON tryon.qr_codes(retailer_id, sku);
CREATE INDEX idx_qr_codes_expires ON tryon.qr_codes(expires_at) WHERE revoked_at IS NULL;

ALTER TABLE tryon.qr_codes ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation_qr_codes ON tryon.qr_codes
    USING (retailer_id = current_setting('app.retailer_id', true)::UUID);

CREATE TABLE tryon.qr_scans (
    id                      VARCHAR(100) PRIMARY KEY,
    qr_code_id              VARCHAR(100) REFERENCES tryon.qr_codes(id),
    retailer_id             UUID NOT NULL REFERENCES public.retailers(id),
    shopper_ref             VARCHAR(200) NOT NULL,
    tryon_id                UUID REFERENCES tryon.tryons(id),
    scanned_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    converted_to_purchase   BOOLEAN NOT NULL DEFAULT FALSE,
    purchased_at            TIMESTAMPTZ,
    purchase_amount_cents   INTEGER
);

CREATE INDEX idx_qr_scans_retailer ON tryon.qr_scans(retailer_id, scanned_at DESC);
CREATE INDEX idx_qr_scans_unconverted ON tryon.qr_scans(retailer_id, converted_to_purchase)
    WHERE converted_to_purchase = FALSE;
CREATE INDEX idx_qr_scans_tryon ON tryon.qr_scans(tryon_id) WHERE tryon_id IS NOT NULL;

ALTER TABLE tryon.qr_scans ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation_qr_scans ON tryon.qr_scans
    USING (retailer_id = current_setting('app.retailer_id', true)::UUID);

CREATE TABLE tryon.attributions (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    retailer_id             UUID NOT NULL REFERENCES public.retailers(id),
    tryon_id                UUID NOT NULL REFERENCES tryon.tryons(id),
    qr_scan_id              VARCHAR(100) REFERENCES tryon.qr_scans(id),
    order_id                VARCHAR(200) NOT NULL,
    order_total_cents       INTEGER NOT NULL,
    purchase_channel        VARCHAR(20) NOT NULL DEFAULT 'in_store',
    attributed_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    billed_amount_cents     INTEGER NOT NULL DEFAULT 0,
    billed_at               TIMESTAMPTZ,
    UNIQUE(retailer_id, order_id)
);

CREATE INDEX idx_attributions_retailer ON tryon.attributions(retailer_id, attributed_at DESC);
CREATE INDEX idx_attributions_tryon ON tryon.attributions(tryon_id);
CREATE INDEX idx_attributions_unbilled ON tryon.attributions(billed_at)
    WHERE billed_at IS NULL;

ALTER TABLE tryon.attributions ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation_attributions ON tryon.attributions
    USING (retailer_id = current_setting('app.retailer_id', true)::UUID);
