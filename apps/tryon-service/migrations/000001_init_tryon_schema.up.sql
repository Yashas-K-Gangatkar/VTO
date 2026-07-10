DROP TYPE IF EXISTS tryon_status;
CREATE TYPE tryon_status AS ENUM ('pending', 'processing', 'succeeded', 'failed', 'expired');

CREATE TABLE tryon.tryons (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    retailer_id     UUID NOT NULL REFERENCES public.retailers(id),
    shopper_ref     VARCHAR(200) NOT NULL,
    body_profile_id UUID NOT NULL,
    sku_id          UUID NOT NULL,
    garment_sku     VARCHAR(200) NOT NULL,
    size            VARCHAR(20),
    view            VARCHAR(20) NOT NULL DEFAULT 'front',
    status          tryon_status NOT NULL DEFAULT 'pending',
    image_url       VARCHAR(1000),
    image_expires_at TIMESTAMPTZ,
    thumbnail_url   VARCHAR(1000),
    quality_score   FLOAT,
    model_version   VARCHAR(50),
    render_time_ms  INTEGER,
    error_code      VARCHAR(50),
    error_detail    TEXT,
    cache_key       VARCHAR(200),
    billed          BOOLEAN NOT NULL DEFAULT FALSE,
    billed_at       TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at    TIMESTAMPTZ
);

CREATE INDEX idx_tryons_retailer ON tryon.tryons(retailer_id, created_at DESC);
CREATE INDEX idx_tryons_cache_key ON tryon.tryons(cache_key) WHERE status = 'succeeded';
CREATE INDEX idx_tryons_status ON tryon.tryons(status) WHERE status IN ('pending', 'processing');
CREATE INDEX idx_tryons_shopper ON tryon.tryons(retailer_id, shopper_ref, created_at DESC);

CREATE TABLE tryon.tryon_views (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tryon_id        UUID NOT NULL REFERENCES tryon.tryons(id),
    view            VARCHAR(20) NOT NULL,
    image_url       VARCHAR(1000),
    status          tryon_status NOT NULL DEFAULT 'pending',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_tryon_views_tryon ON tryon.tryon_views(tryon_id);
