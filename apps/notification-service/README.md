# notification-service

Email + dashboard alerts. Templated via Handlebars.

## Configuration

All config via environment variables. See `internal/config/config.go`.

## Run locally

```bash
go run ./cmd/server
```

Health check: `curl http://localhost:8088/health`

## Tests

```bash
go test ./...
```
