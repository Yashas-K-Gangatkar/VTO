DROP TYPE IF EXISTS digitization_status;
CREATE TYPE digitization_status AS ENUM ('pending', 'processing', 'ready', 'failed', 'manual_qc');

CREATE TABLE catalog.skus (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    retailer_id UUID NOT NULL REFERENCES public.retailers(id),
    sku         VARCHAR(200) NOT NULL,
    name        VARCHAR(500),
    category    VARCHAR(100),
    gender      VARCHAR(20),
    color       VARCHAR(100),
    fabric      VARCHAR(100),
    metadata    JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at  TIMESTAMPTZ
);

CREATE INDEX idx_skus_retailer_sku ON catalog.skus(retailer_id, sku);
CREATE INDEX idx_skus_category ON catalog.skus(retailer_id, category);

CREATE TABLE catalog.garment_representations (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sku_id                UUID NOT NULL REFERENCES catalog.skus(id),
    retailer_id           UUID NOT NULL REFERENCES public.retailers(id),
    front_image_url       VARCHAR(1000),
    back_image_url        VARCHAR(1000),
    segmentation_mask_url VARCHAR(1000),
    attributes            JSONB,
    texture_embedding     FLOAT[],
    quality_score         FLOAT,
    digitization_status   digitization_status NOT NULL DEFAULT 'pending',
    digitization_version  VARCHAR(50),
    digitized_at          TIMESTAMPTZ,
    failure_reason        TEXT,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_garment_rep_sku ON catalog.garment_representations(sku_id);
CREATE INDEX idx_garment_rep_status ON catalog.garment_representations(digitization_status);

CREATE TABLE catalog.digitization_jobs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    retailer_id     UUID NOT NULL REFERENCES public.retailers(id),
    sku_id          UUID NOT NULL REFERENCES catalog.skus(id),
    batch_id        UUID,
    status          digitization_status NOT NULL DEFAULT 'pending',
    started_at      TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,
    error_code      VARCHAR(50),
    error_detail    TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_digitization_jobs_status ON catalog.digitization_jobs(status);
