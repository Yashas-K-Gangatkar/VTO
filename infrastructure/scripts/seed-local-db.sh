#!/usr/bin/env bash
# Seed local database with test data
# Usage: make seed
set -euo pipefail

DATABASE_URL="postgres://vto:dev_password_change_me@localhost:5432/vto?sslmode=disable"
DEV_RETAILER_ID="00000000-0000-0000-0000-000000000001"

echo "==> Seeding local database..."

# 1. Dashboard user
psql "$DATABASE_URL" <<EOF
INSERT INTO dashboard.dashboard_users (id, retailer_id, email, name, role)
VALUES (
    '00000000-0000-0000-0000-000000000010',
    '$DEV_RETAILER_ID',
    'admin@dev-retailer.example',
    'Dev Admin',
    'admin'
) ON CONFLICT (email) DO NOTHING;
EOF

# 2. Sample SKUs (10 SKUs across categories)
psql "$DATABASE_URL" <<EOF
INSERT INTO catalog.skus (retailer_id, sku, name, category, gender, color, fabric) VALUES
('$DEV_RETAILER_ID', 'DEV-SKU-001', 'Silk Wrap Dress',       'dress',     'women',  'emerald', 'silk'),
('$DEV_RETAILER_ID', 'DEV-SKU-002', 'Wool Blazer',            'outerwear', 'women',  'black',   'wool'),
('$DEV_RETAILER_ID', 'DEV-SKU-003', 'Cotton Tee',             'top',       'unisex', 'white',   'cotton'),
('$DEV_RETAILER_ID', 'DEV-SKU-004', 'Denim Jeans',            'bottom',    'men',    'indigo',  'denim'),
('$DEV_RETAILER_ID', 'DEV-SKU-005', 'Linen Shirt',            'top',       'men',    'beige',   'linen'),
('$DEV_RETAILER_ID', 'DEV-SKU-006', 'Knit Sweater',           'top',       'women',  'cream',   'knit'),
('$DEV_RETAILER_ID', 'DEV-SKU-007', 'Pleated Skirt',          'bottom',    'women',  'navy',    'woven'),
('$DEV_RETAILER_ID', 'DEV-SKU-008', 'Tailored Trousers',      'bottom',    'men',    'charcoal','wool'),
('$DEV_RETAILER_ID', 'DEV-SKU-009', 'Maxi Dress',             'dress',     'women',  'floral',  'rayon'),
('$DEV_RETAILER_ID', 'DEV-SKU-010', 'Cashmere Cardigan',      'outerwear', 'women',  'camel',   'wool')
ON CONFLICT (retailer_id, sku) DO NOTHING;
EOF

# 3. Pricing tier
psql "$DATABASE_URL" <<EOF
INSERT INTO billing.pricing_tiers (retailer_id, name, min_volume, max_volume, price_per_tryon_cents, minimum_monthly_commit_cents, effective_from)
VALUES (
    '$DEV_RETAILER_ID',
    'Default',
    0, NULL,
    15,   -- \$0.15 per try-on
    200000, -- \$2,000 minimum monthly commit
    NOW()
) ON CONFLICT DO NOTHING;
EOF

# 4. Webhook endpoint (pointing to a placeholder; replace with your webhook receiver)
psql "$DATABASE_URL" <<EOF
INSERT INTO webhooks.endpoints (retailer_id, url, secret_hash, events, is_active)
VALUES (
    '$DEV_RETAILER_ID',
    'https://example.com/webhooks/vto',
    crypt('dev_webhook_secret_dev_only', gen_salt('bf')),
    ARRAY['tryon.succeeded', 'tryon.viewed', 'billing.threshold_reached'],
    true
) ON CONFLICT DO NOTHING;
EOF

echo "==> Seed complete."
echo "    Retailer:        $DEV_RETAILER_ID"
echo "    Dashboard user:  admin@dev-retailer.example"
echo "    Sample SKUs:     10 (DEV-SKU-001 through DEV-SKU-010)"
echo ""
echo "Note: To use the dashboard locally, you'll need to create an Auth0 user with email admin@dev-retailer.example."
