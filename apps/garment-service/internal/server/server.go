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

    "github.com/vto/garment-service/internal/config"
    "github.com/vto/garment-service/internal/garment"
    "github.com/vto/garment-service/internal/handler"
    "github.com/vto/garment-service/internal/middleware"
    "github.com/vto/garment-service/internal/qrcode"
    vtos3 "github.com/vto/garment-service/internal/s3"
)

var Version = "0.1.0-dev"

type Server struct {
    cfg    *config.Config
    logger zerolog.Logger
    pool   *pgxpool.Pool
    s3     *vtos3.Client
}

func New(cfg *config.Config, logger zerolog.Logger, pool *pgxpool.Pool, s3 *vtos3.Client) *Server {
    return &Server{cfg: cfg, logger: logger, pool: pool, s3: s3}
}

func (s *Server) Router() http.Handler {
    r := chi.NewRouter()

    garmentSvc := garment.New(s.pool, s.s3)
    qrSvc := qrcode.NewQRCodeService(s.s3, s.cfg.QRCodeTokenSecret, s.cfg.QRCodeTokenTTLHours)

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
        r.Get("/qr-codes/verify/{payload}", handler.VerifyQRCode(qrSvc))

        r.Group(func(r chi.Router) {
            r.Use(middleware.JWTAuth(s.cfg.AuthJWKSURL))

            r.Post("/catalog/skus", handler.CreateSKU(garmentSvc))
            r.Get("/catalog/skus", handler.ListSKUs(garmentSvc))
            r.Get("/catalog/skus/{sku}", handler.GetSKU(garmentSvc))
            r.Delete("/catalog/skus/{sku}", handler.DeleteSKU(garmentSvc))

            r.Post("/qr-codes", handler.GenerateQRCode(qrSvc))
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
        s.logger.Info().Str("addr", srv.Addr).Str("version", Version).Msg("garment-service starting")
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
