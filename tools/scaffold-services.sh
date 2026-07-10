#!/usr/bin/env bash
# scaffold-services.sh — Create scaffolds for all backend Go services
# Idempotent: skips services that already have a go.mod.
#
# Usage: ./tools/scaffold-services.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Services and their port assignments
declare -A SERVICES=(
  [auth-service]=8081
  [body-service]=8082
  [garment-service]=8083
  [tryon-service]=8084
  [inference-gateway]=8090
  [analytics-service]=8085
  [billing-service]=8086
  [webhook-service]=8087
  [notification-service]=8088
  [admin-service]=8089
  [dashboard-api]=9000
)

# Service descriptions (for READMEs)
declare -A DESCRIPTIONS=(
  [auth-service]="Token issuance, validation, revocation. API key management. Biometric consent recording."
  [body-service]="Body profile CRUD. Stores SMPL-X parameters encrypted at rest. Triggers async fitting."
  [garment-service]="Catalog CRUD. Tracks digitization status. Triggers digitization pipeline."
  [tryon-service]="Try-on job orchestration. The main product flow. Caches results 24h."
  [inference-gateway]="GPU pool manager. Submits jobs to Triton. Handles spot reclamation. Autoscaling."
  [analytics-service]="Event ingestion → Kafka → ClickHouse. Powers dashboards."
  [billing-service]="Usage metering + Stripe integration. Generates invoices."
  [webhook-service]="Outbound webhook delivery with retries. Disables endpoints after 6 failures."
  [notification-service]="Email + dashboard alerts. Templated via Handlebars."
  [admin-service]="Internal admin API. Tenant management, audit log, feature flags."
  [dashboard-api]="Backend-for-Frontend for retailer dashboard. SSO, RBAC, WebSocket."
)

# Databases used (for docker-compose env wiring)
declare -A DATABASES=(
  [auth-service]=postgresql://vto:dev_password_change_me@postgres:5432/vto?sslmode=disable
  [body-service]=postgresql://vto:dev_password_change_me@postgres:5432/vto?sslmode=disable
  [garment-service]=postgresql://vto:dev_password_change_me@postgres:5432/vto?sslmode=disable
  [tryon-service]=postgresql://vto:dev_password_change_me@postgres:5432/vto?sslmode=disable
  [inference-gateway]=""
  [analytics-service]=postgresql://vto:dev_password_change_me@postgres:5432/vto?sslmode=disable
  [billing-service]=postgresql://vto:dev_password_change_me@postgres:5432/vto?sslmode=disable
  [webhook-service]=postgresql://vto:dev_password_change_me@postgres:5432/vto?sslmode=disable
  [notification-service]=postgresql://vto:dev_password_change_me@postgres:5432/vto?sslmode=disable
  [admin-service]=postgresql://vto:dev_password_change_me@postgres:5432/vto?sslmode=disable
  [dashboard-api]=postgresql://vto:dev_password_change_me@postgres:5432/vto?sslmode=disable
)

for svc in "${!SERVICES[@]}"; do
  port=${SERVICES[$svc]}
  desc=${DESCRIPTIONS[$svc]}
  db=${DATABASES[$svc]}

  svc_dir="apps/$svc"

  if [ -f "$svc_dir/go.mod" ]; then
    echo "  ✓ $svc (already scaffolded)"
    continue
  fi

  echo "  → scaffolding $svc (port $port)"
  mkdir -p "$svc_dir/cmd/server" "$svc_dir/internal/config" "$svc_dir/internal/handler" "$svc_dir/internal/server" "$svc_dir/migrations"

  # go.mod
  cat > "$svc_dir/go.mod" <<EOF
module github.com/vto/$svc

go 1.22

require (
        github.com/go-chi/chi/v5 v5.0.12
        github.com/rs/zerolog v1.32.0
        github.com/kelseyhightower/envconfig v1.4.0
)
EOF

  # config.go
  cat > "$svc_dir/internal/config/config.go" <<EOF
// Package config holds environment-driven configuration for $svc.
package config

import (
        "fmt"

        "github.com/kelseyhightower/envconfig"
)

// Config is the $svc configuration.
type Config struct {
        Env      string \`envconfig:"ENV" default:"dev"\`
        LogLevel string \`envconfig:"LOG_LEVEL" default:"info"\`
        Port     int    \`envconfig:"PORT" default:"$port"\`
EOF

  if [ -n "$db" ]; then
    cat >> "$svc_dir/internal/config/config.go" <<EOF
        DatabaseURL string \`envconfig:"DATABASE_URL" default:"$db"\`
        RedisURL    string \`envconfig:"REDIS_URL" default:"redis://redis:6379"\`
EOF
  fi

  cat >> "$svc_dir/internal/config/config.go" <<EOF
}

// Load reads configuration from environment variables.
func Load() (*Config, error) {
        var cfg Config
        if err := envconfig.Process("", &cfg); err != nil {
                return nil, fmt.Errorf("envconfig: %w", err)
        }
        return &cfg, nil
}
EOF

  # health handler
  cat > "$svc_dir/internal/handler/health.go" <<EOF
// Package handler holds HTTP handlers for $svc.
package handler

import (
        "encoding/json"
        "net/http"
        "runtime"
        "time"
)

// HealthResponse is the /health response.
type HealthResponse struct {
        Status    string    \`json:"status"\`
        Version   string    \`json:"version"\`
        Timestamp time.Time \`json:"timestamp"\`
        GoVersion string    \`json:"go_version"\`
}

// Health handles GET /health.
func Health(version string) http.HandlerFunc {
        return func(w http.ResponseWriter, r *http.Request) {
                w.Header().Set("Content-Type", "application/json")
                _ = json.NewEncoder(w).Encode(HealthResponse{
                        Status:    "ok",
                        Version:   version,
                        Timestamp: time.Now().UTC(),
                        GoVersion: runtime.Version(),
                })
        }
}
EOF

  # server.go
  cat > "$svc_dir/internal/server/server.go" <<EOF
// Package server wires up the HTTP server for $svc.
package server

import (
        "context"
        "net/http"
        "time"

        "github.com/go-chi/chi/v5"
        "github.com/rs/zerolog"

        "github.com/vto/$svc/internal/config"
        "github.com/vto/$svc/internal/handler"
)

// Version is the service version. Set at build time via -ldflags.
var Version = "0.1.0-dev"

// Server holds dependencies for the HTTP server.
type Server struct {
        cfg    *config.Config
        logger zerolog.Logger
}

// New creates a new Server.
func New(cfg *config.Config, logger zerolog.Logger) *Server {
        return &Server{cfg: cfg, logger: logger}
}

// Router returns the chi router.
func (s *Server) Router() http.Handler {
        r := chi.NewRouter()
        r.Get("/health", handler.Health(Version))
        // TODO: add service-specific routes
        return r
}

// Start begins serving HTTP. Blocks until ctx is canceled.
func (s *Server) Start(ctx context.Context) error {
        srv := &http.Server{
                Addr:              ":" + itoa(s.cfg.Port),
                Handler:           s.Router(),
                ReadHeaderTimeout: 5 * time.Second,
                ReadTimeout:       30 * time.Second,
                WriteTimeout:      30 * time.Second,
                IdleTimeout:       120 * time.Second,
        }

        errCh := make(chan error, 1)
        go func() {
                s.logger.Info().Str("addr", srv.Addr).Str("version", Version).Msg("$svc starting")
                if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
                        errCh <- err
                }
        }()

        select {
        case <-ctx.Done():
                shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
                defer cancel()
                return srv.Shutdown(shutdownCtx)
        case err := <-errCh:
                return err
        }
}

func itoa(i int) string {
        if i == 0 {
                return "0"
        }
        var buf [20]byte
        pos := len(buf)
        for i > 0 {
                pos--
                buf[pos] = byte('0' + i%10)
                i /= 10
        }
        return string(buf[pos:])
}
EOF

  # main.go
  cat > "$svc_dir/cmd/server/main.go" <<EOF
// Package main is the entry point for $svc.
package main

import (
        "context"
        "os"
        "os/signal"
        "syscall"
        "time"

        "github.com/rs/zerolog"
        "github.com/rs/zerolog/log"

        "github.com/vto/$svc/internal/config"
        "github.com/vto/$svc/internal/server"
)

func main() {
        zerolog.TimeFieldFormat = time.RFC3339Nano
        log.Logger = log.Output(os.Stdout).With().Str("service", "$svc").Logger()

        cfg, err := config.Load()
        if err != nil {
                log.Fatal().Err(err).Msg("failed to load config")
        }

        level, err := zerolog.ParseLevel(cfg.LogLevel)
        if err != nil {
                level = zerolog.InfoLevel
        }
        zerolog.SetGlobalLevel(level)

        srv := server.New(cfg, log.Logger)

        ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
        defer stop()

        if err := srv.Start(ctx); err != nil {
                log.Fatal().Err(err).Msg("server error")
        }

        log.Info().Msg("$svc stopped")
}
EOF

  # Dockerfile
  cat > "$svc_dir/Dockerfile" <<'EOF'
# syntax=docker/dockerfile:1.6

FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download || true
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /svc ./cmd/server

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /svc /svc
USER nonroot
EXPOSE 8080
ENTRYPOINT ["/svc"]
EOF

  # README.md
  cat > "$svc_dir/README.md" <<EOF
# $svc

$desc

## Configuration

All config via environment variables. See \`internal/config/config.go\`.

## Run locally

\`\`\`bash
go run ./cmd/server
\`\`\`

Health check: \`curl http://localhost:$port/health\`

## Tests

\`\`\`bash
go test ./...
\`\`\`
EOF

  # .gitkeep for migrations
  touch "$svc_dir/migrations/.gitkeep"

  echo "    created at $svc_dir"
done

echo ""
echo "Done. All services scaffolded."
echo "Next: implement service-specific logic in each app's internal/ packages."
