# admin-service

Internal admin API. Tenant management, audit log, feature flags.

## Configuration

All config via environment variables. See `internal/config/config.go`.

## Run locally

```bash
go run ./cmd/server
```

Health check: `curl http://localhost:8089/health`

## Tests

```bash
go test ./...
```
