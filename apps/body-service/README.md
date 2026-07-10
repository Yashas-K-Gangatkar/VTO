# body-service

Body profile CRUD. Stores SMPL-X parameters encrypted at rest. Triggers async fitting.

## Configuration

All config via environment variables. See `internal/config/config.go`.

## Run locally

```bash
go run ./cmd/server
```

Health check: `curl http://localhost:8082/health`

## Tests

```bash
go test ./...
```
