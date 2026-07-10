# Body Service

Body profile CRUD with encrypted storage. Stores SMPL-X parameters encrypted at rest.

Per DR-011: biometric data, 12-month expiry, AES-256 encryption, delete-on-demand within 72h.
Per DR-075: multi-tenancy via retailer_id + RLS.

## Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | /health | None | Liveness check |
| POST | /v1/body_profiles | JWT (shopper) | Create body profile (multipart upload) |
| GET | /v1/body_profiles/{id} | JWT (shopper) | Get body profile metadata |
| DELETE | /v1/body_profiles/{id} | JWT (shopper) | Delete body profile (72h SLA) |

## Architecture

- Scan data encrypted client-side with AES-256-GCM before S3 upload
- Encryption key loaded from disk (dev) or AWS KMS (prod)
- Raw scan data deleted from S3 within 24h of profile creation
- Body profiles expire after 12 months by default
- All tables have RLS enabled

## Run locally

    go run ./cmd/server
