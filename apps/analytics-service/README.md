# analytics-service

Event ingestion → Kafka → ClickHouse. Powers dashboards.

## Configuration

All config via environment variables. See `internal/config/config.go`.

## Run locally

```bash
go run ./cmd/server
```

Health check: `curl http://localhost:8085/health`

## Tests

```bash
go test ./...
```
