# Try-On Service

Try-on job orchestration. The main product flow.

Per DR-032: 24h result caching, no rebilling for cached views.
Per DR-025: billing occurs on tryon.viewed event (not on generation).

## Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | /health | None | Liveness check |
| POST | /v1/tryons | JWT (shopper) | Request try-on generation |
| GET | /v1/tryons/{id} | JWT (shopper) | Poll try-on status |
| POST | /v1/tryons/{id}/viewed | JWT (shopper) | Mark try-on as viewed (billing trigger) |

## Flow

1. Shopper taps Try It On
2. SDK calls POST /v1/tryons with body_profile_id + garment_sku
3. Service checks 24h cache (cache_key = hash of all inputs)
4. Cache hit: return cached result immediately (not billed again)
5. Cache miss: create pending record, return tryon_id
6. Inference Gateway processes job async
7. SDK polls GET /v1/tryons/{id} until status=succeeded
8. Shopper views image
9. SDK calls POST /v1/tryons/{id}/viewed - THIS is the billing trigger
10. Redis dedup prevents double-billing within 24h

## Run locally

    go run ./cmd/server
