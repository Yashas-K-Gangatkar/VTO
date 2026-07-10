# tryon-service

Try-on job orchestration. The main product flow. Caches results 24h.

## Configuration

All config via environment variables. See `internal/config/config.go`.

## Run locally

```bash
go run ./cmd/server
```

Health check: `curl http://localhost:8084/health`

## Tests

```bash
go test ./...
```
