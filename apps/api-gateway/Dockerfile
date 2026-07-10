# syntax=docker/dockerfile:1.6

# ============================================================
# Build stage
# ============================================================
FROM golang:1.22-alpine AS builder

WORKDIR /app

# Cache deps
COPY go.mod go.sum ./
RUN go mod download

# Copy source and build
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build \
    -ldflags="-s -w -X github.com/vto/api-gateway/internal/server.Version=$(git rev-parse --short HEAD 2>/dev/null || echo dev)" \
    -o /api-gateway \
    ./cmd/server

# ============================================================
# Runtime stage (distroless — minimal attack surface)
# ============================================================
FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=builder /api-gateway /api-gateway

USER nonroot
EXPOSE 8080

ENTRYPOINT ["/api-gateway"]
