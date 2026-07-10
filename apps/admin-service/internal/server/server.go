// Package server wires up the HTTP server for admin-service.
package server

import (
        "context"
        "net/http"
        "time"

        "github.com/go-chi/chi/v5"
        "github.com/rs/zerolog"

        "github.com/vto/admin-service/internal/config"
        "github.com/vto/admin-service/internal/handler"
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
                s.logger.Info().Str("addr", srv.Addr).Str("version", Version).Msg("admin-service starting")
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
