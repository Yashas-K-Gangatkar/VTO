-- VTO Postgres initialization
-- Creates schemas and extensions. Table creation is handled by golang-migrate.

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Schemas (one per service boundary — see DR-075 for multi-tenancy model)
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS body;
CREATE SCHEMA IF NOT EXISTS catalog;
CREATE SCHEMA IF NOT EXISTS tryon;
CREATE SCHEMA IF NOT EXISTS billing;
CREATE SCHEMA IF NOT EXISTS webhooks;
CREATE SCHEMA IF NOT EXISTS dashboard;
CREATE SCHEMA IF NOT EXISTS admin;

-- Top-level retailer table (referenced by all schemas)
CREATE TABLE IF NOT EXISTS public.retailers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(500) NOT NULL,
    legal_name VARCHAR(500),
    billing_email VARCHAR(500),
    technical_contact_email VARCHAR(500),
    status VARCHAR(50) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    settings JSONB NOT NULL DEFAULT '{}'
);

-- Seed one dev retailer for local testing
INSERT INTO public.retailers (id, name, legal_name, billing_email, technical_contact_email)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'Dev Retailer',
    'Dev Retailer Inc.',
    'billing@dev-retailer.example',
    'tech@dev-retailer.example'
) ON CONFLICT (id) DO NOTHING;

-- Enable Row-Level Security on all tenant-scoped tables
-- (Will be applied per-table by migrations as tables are created)
-- ALTER TABLE auth.api_keys ENABLE ROW LEVEL SECURITY;
-- CREATE POLICY tenant_isolation ON auth.api_keys
--   USING (retailer_id = current_setting('app.retailer_id')::UUID);
