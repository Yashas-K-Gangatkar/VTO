# inference-gateway

GPU pool manager. Submits jobs to Triton. Handles spot reclamation. Autoscaling.

## Configuration

All config via environment variables. See `internal/config/config.go`.

## Run locally

```bash
go run ./cmd/server
```

Health check: `curl http://localhost:8090/health`

## Tests

```bash
go test ./...
```
