// Package server wires up the HTTP server for the API Gateway.
package server

import (
	"context"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/cors"
	"github.com/redis/go-redis/v9"
	"github.com/rs/zerolog"

	"github.com/vto/api-gateway/internal/config"
	"github.com/vto/api-gateway/internal/handler"
	"github.com/vto/api-gateway/internal/middleware"
	"github.com/vto/api-gateway/internal/proxy"
)

// Version is the API Gateway version. Set at build time via -ldflags.
var Version = "0.1.0-dev"

// Server holds dependencies for the HTTP server.
type Server struct {
	cfg    *config.Config
	logger zerolog.Logger
	rdb    *redis.Client
	router *proxy.Router
}

// New creates a new Server.
func New(cfg *config.Config, logger zerolog.Logger, rdb *redis.Client) (*Server, error) {
	routes := map[string]string{
		"/v1/tokens":           cfg.AuthServiceURL,
		"/v1/.well-known":      cfg.AuthServiceURL,
		"/v1/api-keys":         cfg.AuthServiceURL,
		"/v1/consent":          cfg.AuthServiceURL,
		"/v1/body_profiles":    cfg.BodyServiceURL,
		"/v1/catalog":          cfg.GarmentServiceURL,
		"/v1/tryons":           cfg.TryOnServiceURL,
		"/v1/events":           cfg.AnalyticsServiceURL,
		"/v1/attribution":      cfg.AnalyticsServiceURL,
		"/v1/analytics":        cfg.AnalyticsServiceURL,
		"/v1/billing":          cfg.BillingServiceURL,
		"/v1/webhooks":         cfg.WebhookServiceURL,
	}

	router, err := proxy.NewRouter(routes)
	if err != nil {
		return nil, err
	}

	return &Server{
		cfg:    cfg,
		logger: logger,
		rdb:    rdb,
		router: router,
	}, nil
}

// Router returns the chi router with all middleware and routes wired.
func (s *Server) Router() http.Handler {
	r := chi.NewRouter()

	// Global middleware
	r.Use(middleware.RequestID)
	r.Use(middleware.Recoverer(s.logger))
	r.Use(middleware.Logger(s.logger))
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   []string{"*"}, // Tighten in production
		AllowedMethods:   []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "X-Request-Id", "Idempotency-Key"},
		ExposedHeaders:   []string{"X-Request-Id", "X-RateLimit-Limit", "X-RateLimit-Remaining", "Retry-After"},
		AllowCredentials: false,
		MaxAge:           300,
	}))

	// Health (no rate limit)
	r.Get("/v1/health", handler.Health(Version))
	r.Get("/health", handler.Health(Version))

	// Rate-limited public API
	r.Group(func(r chi.Router) {
		rl := middleware.NewRateLimiter(s.rdb, s.cfg.RateLimitDefault)
		r.Use(rl.Middleware())
		r.Handle("/v1/*", s.router.Handler())
	})

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
		s.logger.Info().Str("addr", srv.Addr).Str("version", Version).Msg("api-gateway starting")
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
