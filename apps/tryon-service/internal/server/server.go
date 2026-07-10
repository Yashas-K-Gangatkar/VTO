package server

import (
    "context"
    "net/http"
    "strconv"
    "time"

    "github.com/go-chi/chi/v5"
    "github.com/go-chi/cors"
    "github.com/jackc/pgx/v5/pgxpool"
    "github.com/rs/zerolog"

    "github.com/tryon-service/internal/cache"
    "github.com/tryon-service/internal/config"
    "github.com/tryon-service/internal/handler"
    "github.com/tryon-service/internal/middleware"
    "github.com/tryon-service/internal/tryon"
)

var Version = "0.1.0-dev"

type Server struct {
    cfg    *config.Config
    logger zerolog.Logger
    pool   *pgxpool.Pool
    cache  *cache.Redis
}

func New(cfg *config.Config, logger zerolog.Logger, pool *pgxpool.Pool, cache *cache.Redis) *Server {
    return &Server{cfg: cfg, logger: logger, pool: pool, cache: cache}
}

func (s *Server) Router() http.Handler {
    r := chi.NewRouter()

    tryonSvc := tryon.New(s.pool, s.cache, s.cfg.CacheTTLHours)

    r.Use(middleware.RequestID)
    r.Use(cors.Handler(cors.Options{
        AllowedOrigins:   []string{"*"},
        AllowedMethods:   []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
        AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "X-Request-Id", "Idempotency-Key"},
        ExposedHeaders:   []string{"X-Request-Id"},
        AllowCredentials: false,
        MaxAge:           300,
    }))

    r.Get("/health", handler.Health(Version))

    r.Route("/v1", func(r chi.Router) {
        r.Group(func(r chi.Router) {
            r.Use(middleware.JWTAuth(s.cfg.AuthJWKSURL))

            r.Post("/tryons", handler.CreateTryOn(tryonSvc))
            r.Get("/tryons/{id}", handler.GetTryOn(tryonSvc))
            r.Post("/tryons/{id}/viewed", handler.MarkViewed(tryonSvc))
            r.Post("/tryons/qr-scan", handler.CreateTryOnFromQRScan(tryonSvc, s.cfg.GarmentServiceURL))
        })
    })

    return r
}

func (s *Server) Start(ctx context.Context) error {
    srv := &http.Server{
        Addr:              ":" + strconv.Itoa(s.cfg.Port),
        Handler:           s.Router(),
        ReadHeaderTimeout: 5 * time.Second,
        ReadTimeout:       30 * time.Second,
        WriteTimeout:      30 * time.Second,
        IdleTimeout:       120 * time.Second,
    }

    errCh := make(chan error, 1)
    go func() {
        s.logger.Info().Str("addr", srv.Addr).Str("version", Version).Msg("tryon-service starting")
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
