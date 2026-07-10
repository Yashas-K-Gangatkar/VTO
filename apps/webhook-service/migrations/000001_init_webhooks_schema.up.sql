-- ============================================================
-- Migration 000001: Initialize webhooks schema
-- ============================================================
-- Per DR-041: 6 retries over 24h, disable after 6 failures
-- Per DR-027: HMAC-SHA256 signed deliveries

CREATE TABLE webhooks.endpoints (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    retailer_id     UUID NOT NULL REFERENCES public.retailers(id),
    url             VARCHAR(1000) NOT NULL,
    secret_hash     VARCHAR(128) NOT NULL,
    events          TEXT[] NOT NULL,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    disabled_at     TIMESTAMPTZ,
    disabled_reason TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_webhook_endpoints_retailer ON webhooks.endpoints(retailer_id) WHERE is_active = TRUE;
CREATE INDEX idx_webhook_endpoints_events ON webhooks.endpoints USING GIN (events);

ALTER TABLE webhooks.endpoints ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation_webhook_endpoints ON webhooks.endpoints
    USING (retailer_id = current_setting('app.retailer_id', true)::UUID);

CREATE TABLE webhooks.deliveries (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    endpoint_id     UUID NOT NULL REFERENCES webhooks.endpoints(id),
    retailer_id     UUID NOT NULL REFERENCES public.retailers(id),
    event_type      VARCHAR(100) NOT NULL,
    payload         JSONB NOT NULL,
    signature       VARCHAR(200) NOT NULL,
    attempt_number  INTEGER NOT NULL DEFAULT 1,
    status          VARCHAR(20) NOT NULL,
    response_code   INTEGER,
    response_body   TEXT,
    next_retry_at   TIMESTAMPTZ,
    delivered_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_webhook_deliveries_pending ON webhooks.deliveries(next_retry_at) WHERE status = 'pending';
CREATE INDEX idx_webhook_deliveries_endpoint ON webhooks.deliveries(endpoint_id, created_at DESC);
CREATE INDEX idx_webhook_deliveries_retailer ON webhooks.deliveries(retailer_id, created_at DESC);

ALTER TABLE webhooks.deliveries ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation_webhook_deliveries ON webhooks.deliveries
    USING (retailer_id = current_setting('app.retailer_id', true)::UUID);
