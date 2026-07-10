# auth-service

Token issuance, validation, revocation. API key management. Biometric consent recording.

## Configuration

All config via environment variables. See `internal/config/config.go`.

## Run locally

```bash
go run ./cmd/server
```

Health check: `curl http://localhost:8081/health`

## Tests

```bash
go test ./...
```
