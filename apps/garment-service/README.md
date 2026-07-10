# Garment Service

Catalog CRUD + digitization status + QR code generation.

## Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | /health | None | Liveness check |
| POST | /v1/catalog/skus | JWT | Create a SKU |
| GET | /v1/catalog/skus | JWT | List SKUs |
| GET | /v1/catalog/skus/{sku} | JWT | Get SKU by code |
| DELETE | /v1/catalog/skus/{sku} | JWT | Delete SKU |
| POST | /v1/qr-codes | JWT | Generate QR code for a SKU |
| GET | /v1/qr-codes/verify/{payload} | None | Verify a QR code (public) |

## Run locally

    go run ./cmd/server
