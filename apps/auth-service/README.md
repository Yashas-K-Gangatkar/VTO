# Auth Service

Token issuance, validation, revocation. API key management. Biometric consent recording.

Implements the three-layer auth model from DR-027.

## Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | /health | None | Liveness check |
| GET | /v1/.well-known/jwks.json | None | Public key for JWT verification |
| POST | /v1/tokens | API key | Mint a scoped shopper token |
| POST | /v1/tokens/revoke | API key | Revoke a shopper token |
| POST | /v1/api-keys | API key | Create a new API key |
| GET | /v1/api-keys | API key | List active API keys |
| DELETE | /v1/api-keys/{id} | API key | Revoke an API key |
| POST | /v1/consent | JWT | Record biometric consent |

## Run locally

    go run ./cmd/server

## Tests

    go test ./...
