-- ============================================================
-- Migration 000001: Initialize admin schema
-- ============================================================
-- Internal admin tables — NO RLS (admin service is internal-only, behind VPN + SSO)

CREATE TABLE admin.feature_flags (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    retailer_id     UUID REFERENCES public.retailers(id),
    flag_key        VARCHAR(100) NOT NULL,
    flag_value      JSONB NOT NULL DEFAULT 'false'::jsonb,
    description     TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(retailer_id, flag_key)
);

CREATE INDEX idx_feature_flags_retailer ON admin.feature_flags(retailer_id);
CREATE INDEX idx_feature_flags_key ON admin.feature_flags(flag_key);

CREATE TABLE admin.audit_log (
    id              BIGSERIAL PRIMARY KEY,
    admin_user_id   UUID NOT NULL,
    action          VARCHAR(100) NOT NULL,
    target_type     VARCHAR(50) NOT NULL,
    target_id       VARCHAR(200),
    details         JSONB,
    ip_address      INET,
    user_agent      TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_log_user ON admin.audit_log(admin_user_id, created_at DESC);
CREATE INDEX idx_audit_log_target ON admin.audit_log(target_type, target_id);
CREATE INDEX idx_audit_log_action ON admin.audit_log(action, created_at DESC);

CREATE TABLE admin.internal_users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email           VARCHAR(500) NOT NULL UNIQUE,
    name            VARCHAR(500),
    role            VARCHAR(50) NOT NULL DEFAULT 'support',
    auth0_user_id   VARCHAR(200) UNIQUE,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    last_login_at   TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_internal_users_email ON admin.internal_users(email) WHERE is_active = TRUE;
