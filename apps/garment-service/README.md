# garment-service

Catalog CRUD. Tracks digitization status. Triggers digitization pipeline.

## Configuration

All config via environment variables. See `internal/config/config.go`.

## Run locally

```bash
go run ./cmd/server
```

Health check: `curl http://localhost:8083/health`

## Tests

```bash
go test ./...
```
