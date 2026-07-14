-- ============================================================
-- Migration 000001: Initialize dashboard schema
-- ============================================================
-- Per DR-014: RBAC roles — admin, developer, billing, read-only

CREATE TABLE dashboard.dashboard_users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    retailer_id     UUID NOT NULL REFERENCES public.retailers(id),
    email           VARCHAR(500) NOT NULL,
    name            VARCHAR(500),
    role            VARCHAR(50) NOT NULL DEFAULT 'read_only',
    auth0_user_id   VARCHAR(200) UNIQUE,
    last_login_at   TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(retailer_id, email)
);

CREATE INDEX idx_dashboard_users_retailer ON dashboard.dashboard_users(retailer_id);
CREATE INDEX idx_dashboard_users_auth0 ON dashboard.dashboard_users(auth0_user_id) WHERE auth0_user_id IS NOT NULL;

ALTER TABLE dashboard.dashboard_users ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation_dashboard_users ON dashboard.dashboard_users
    USING (retailer_id = current_setting('app.retailer_id', true)::UUID);

CREATE TABLE dashboard.dashboard_sessions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES dashboard.dashboard_users(id),
    token_hash      VARCHAR(128) NOT NULL,
    expires_at      TIMESTAMPTZ NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_dashboard_sessions_user ON dashboard.dashboard_sessions(user_id);
CREATE INDEX idx_dashboard_sessions_token ON dashboard.dashboard_sessions(token_hash);

ALTER TABLE dashboard.dashboard_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation_dashboard_sessions ON dashboard.dashboard_sessions
    USING (retailer_id = current_setting('app.retailer_id', true)::UUID);
