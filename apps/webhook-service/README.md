# webhook-service

Outbound webhook delivery with retries. Disables endpoints after 6 failures.

## Configuration

All config via environment variables. See `internal/config/config.go`.

## Run locally

```bash
go run ./cmd/server
```

Health check: `curl http://localhost:8087/health`

## Tests

```bash
go test ./...
```
