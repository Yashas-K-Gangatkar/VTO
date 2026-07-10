-- ============================================================
-- Migration 000001: Initialize body schema
-- ============================================================
-- Per DR-011: biometric data, 12-month expiry, encrypted at rest
-- Per DR-075: multi-tenancy via retailer_id + RLS

CREATE TABLE body.body_profiles (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    retailer_id         UUID NOT NULL REFERENCES public.retailers(id),
    shopper_ref         VARCHAR(200) NOT NULL,
    smplx_blob_key      VARCHAR(500) NOT NULL,
    smplx_blob_kms_key_id VARCHAR(200) NOT NULL,
    measurements        JSONB NOT NULL,
    scan_device         VARCHAR(100),
    scan_quality_score  FLOAT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at          TIMESTAMPTZ NOT NULL,
    deleted_at          TIMESTAMPTZ,
    UNIQUE(retailer_id, shopper_ref) WHERE deleted_at IS NULL
);

CREATE INDEX idx_body_profiles_retailer_shopper
    ON body.body_profiles(retailer_id, shopper_ref)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_body_profiles_expiry
    ON body.body_profiles(expires_at)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_body_profiles_pending_deletion
    ON body.body_profiles(deleted_at)
    WHERE deleted_at IS NOT NULL;

ALTER TABLE body.body_profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation_body_profiles ON body.body_profiles
    USING (retailer_id = current_setting('app.retailer_id', true)::UUID);
