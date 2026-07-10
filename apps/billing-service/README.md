# billing-service

Usage metering + Stripe integration. Generates invoices.

## Configuration

All config via environment variables. See `internal/config/config.go`.

## Run locally

```bash
go run ./cmd/server
```

Health check: `curl http://localhost:8086/health`

## Tests

```bash
go test ./...
```
