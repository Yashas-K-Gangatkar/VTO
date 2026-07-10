# API Gateway

The single public entry point for the VTO platform. Routes requests, enforces auth, rate limits, terminates TLS (in production; TLS is terminated by Cloudflare/ALB upstream).

## Responsibilities

- TLS termination (production only; local is plain HTTP)
- JWT validation (via JWKS from auth-service)
- Rate limiting (per-IP via Redis sliding window)
- Request routing to backend services
- Structured access logging
- CORS handling
- Gzip compression (TODO)
- API version routing (`/v1/`, future `/v2/`)

## Routes

| Path prefix            | Upstream service   |
|------------------------|--------------------|
| `/v1/tokens`           | auth-service       |
| `/v1/.well-known`      | auth-service       |
| `/v1/api-keys`         | auth-service       |
| `/v1/consent`          | auth-service       |
| `/v1/body_profiles`    | body-service       |
| `/v1/catalog`          | garment-service    |
| `/v1/tryons`           | tryon-service      |
| `/v1/events`           | analytics-service  |
| `/v1/attribution`      | analytics-service  |
| `/v1/analytics`        | analytics-service  |
| `/v1/billing`          | billing-service    |
| `/v1/webhooks`         | webhook-service    |
| `/v1/health`           | (handled locally)  |

## Configuration

All config via environment variables. See `internal/config/config.go`.

| Var                   | Default                              | Description                  |
|-----------------------|--------------------------------------|------------------------------|
| `ENV`                 | `dev`                                | Environment name             |
| `LOG_LEVEL`           | `info`                               | debug, info, warn, error     |
| `PORT`                | `8080`                               | HTTP listen port             |
| `REDIS_URL`           | `redis://redis:6379`                 | Redis connection string      |
| `JWKS_URL`            | auth-service JWKS endpoint           | JWT verification keys        |
| `RATE_LIMIT_DEFAULT`  | `600`                                | Requests per minute per IP   |

## Run locally

```bash
# From repo root
make dev

# Or directly
go run ./cmd/server
```

Health check: `curl http://localhost:8080/v1/health`

## Tests

```bash
go test ./...
```

## Build

```bash
go build -o bin/api-gateway ./cmd/server
```

Docker:
```bash
docker build -t vto/api-gateway .
```
