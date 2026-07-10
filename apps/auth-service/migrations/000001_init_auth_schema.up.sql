-- ============================================================
-- Migration 000001: Initialize auth schema
-- ============================================================

-- API Keys (server-to-server authentication)
CREATE TABLE auth.api_keys (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    retailer_id     UUID NOT NULL REFERENCES public.retailers(id),
    name            VARCHAR(100) NOT NULL,
    key_hash        VARCHAR(128) NOT NULL,
    key_prefix      VARCHAR(10) NOT NULL,
    scopes          TEXT[] NOT NULL DEFAULT '{"server_to_server"}',
    last_used_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by      UUID,
    revoked_at      TIMESTAMPTZ,
    revoked_reason  TEXT,
    CONSTRAINT chk_key_hash_format CHECK (key_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT chk_key_prefix_format CHECK (key_prefix ~ '^vto_[a-z0-9]{4}$')
);

CREATE INDEX idx_api_keys_key_hash ON auth.api_keys(key_hash) WHERE revoked_at IS NULL;
CREATE INDEX idx_api_keys_retailer ON auth.api_keys(retailer_id) WHERE revoked_at IS NULL;

ALTER TABLE auth.api_keys ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation_api_keys ON auth.api_keys
    USING (retailer_id = current_setting('app.retailer_id', true)::UUID);

-- Consent Records (biometric consent per DR-011)
CREATE TABLE auth.consent_records (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    retailer_id     UUID NOT NULL REFERENCES public.retailers(id),
    shopper_ref     VARCHAR(200) NOT NULL,
    consent_type    VARCHAR(50) NOT NULL,
    consent_version VARCHAR(20) NOT NULL,
    consented_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at      TIMESTAMPTZ,
    ip_address      INET,
    user_agent      TEXT,
    signature       TEXT NOT NULL,
    CONSTRAINT chk_consent_type CHECK (consent_type IN ('body_scan', 'training_use')),
    CONSTRAINT chk_consent_version CHECK (consent_version ~ '^\d+\.\d+$')
);

CREATE INDEX idx_consent_retailer_shopper ON auth.consent_records(retailer_id, shopper_ref);
CREATE INDEX idx_consent_active ON auth.consent_records(retailer_id, shopper_ref, consent_type)
    WHERE revoked_at IS NULL;

ALTER TABLE auth.consent_records ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation_consent ON auth.consent_records
    USING (retailer_id = current_setting('app.retailer_id', true)::UUID);

-- Token Audit
CREATE TABLE auth.token_audit (
    id              BIGSERIAL PRIMARY KEY,
    token_id        VARCHAR(100) NOT NULL,
    retailer_id     UUID NOT NULL REFERENCES public.retailers(id),
    shopper_ref     VARCHAR(200),
    issued_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at      TIMESTAMPTZ NOT NULL,
    revoked_at      TIMESTAMPTZ,
    scopes          TEXT[],
    ip_address      INET
);

CREATE INDEX idx_token_audit_token ON auth.token_audit(token_id);
CREATE INDEX idx_token_audit_retailer ON auth.token_audit(retailer_id, issued_at DESC);
CREATE INDEX idx_token_audit_active ON auth.token_audit(expires_at)
    WHERE revoked_at IS NULL;

ALTER TABLE auth.token_audit ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation_token_audit ON auth.token_audit
    USING (retailer_id = current_setting('app.retailer_id', true)::UUID);

-- JWT Signing Keys
CREATE TABLE auth.signing_keys (
    id              VARCHAR(50) PRIMARY KEY,
    algorithm       VARCHAR(10) NOT NULL DEFAULT 'RS256',
    public_key_pem  TEXT NOT NULL,
    is_active       BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    retired_at      TIMESTAMPTZ,
    CONSTRAINT chk_algorithm CHECK (algorithm IN ('RS256', 'RS384', 'RS512'))
);
