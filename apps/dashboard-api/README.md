# dashboard-api

Backend-for-Frontend for retailer dashboard. SSO, RBAC, WebSocket.

## Configuration

All config via environment variables. See `internal/config/config.go`.

## Run locally

```bash
go run ./cmd/server
```

Health check: `curl http://localhost:9000/health`

## Tests

```bash
go test ./...
```
