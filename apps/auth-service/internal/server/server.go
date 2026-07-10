package server

import (
    "context"
    "net/http"
    "strconv"
    "time"

    "github.com/go-chi/chi/v5"
    "github.com/go-chi/cors"
    "github.com/jackc/pgx/v5/pgxpool"
    "github.com/redis/go-redis/v9"
    "github.com/rs/zerolog"

    "github.com/vto/auth-service/internal/apikey"
    "github.com/vto/auth-service/internal/config"
    "github.com/vto/auth-service/internal/consent"
    "github.com/vto/auth-service/internal/handler"
    "github.com/vto/auth-service/internal/jwt"
    "github.com/vto/auth-service/internal/middleware"
    "github.com/vto/auth-service/internal/token"
)

var Version = "0.1.0-dev"

type Server struct {
    cfg      *config.Config
    logger   zerolog.Logger
    pool     *pgxpool.Pool
    rdb      *redis.Client
    signer   *jwt.Signer
    verifier *jwt.Verifier
}

func New(cfg *config.Config, logger zerolog.Logger, pool *pgxpool.Pool, rdb *redis.Client) (*Server, error) {
    signer, err := jwt.NewSigner(cfg.JWTPrivateKeyPath, cfg.JWTSigningKeyID, cfg.JWTIssuer, cfg.JWTAudience)
    if err != nil {
        return nil, err
    }

    verifier, err := jwt.NewVerifier(cfg.JWTPublicKeyPath, cfg.JWTSigningKeyID, cfg.JWTIssuer, cfg.JWTAudience)
    if err != nil {
        return nil, err
    }

    return &Server{
        cfg:      cfg,
        logger:   logger,
        pool:     pool,
        rdb:      rdb,
        signer:   signer,
        verifier: verifier,
    }, nil
}

func (s *Server) Router() http.Handler {
    r := chi.NewRouter()

    apiKeySvc := apikey.New(s.pool)
    consentSvc := consent.New(s.pool)
    tokenSvc := token.New(s.pool, s.rdb, s.signer)

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
    r.Get("/v1/.well-known/jwks.json", handler.JWKS(s.verifier))

    r.Route("/v1", func(r chi.Router) {
        r.Group(func(r chi.Router) {
            r.Use(middleware.APIKeyAuth(apiKeySvc))

            r.Post("/tokens", handler.MintToken(tokenSvc, s.cfg.DefaultTokenTTLSeconds))
            r.Post("/tokens/revoke", handler.RevokeToken(tokenSvc))

            r.Post("/api-keys", handler.CreateAPIKey(apiKeySvc))
            r.Get("/api-keys", handler.ListAPIKeys(apiKeySvc))
            r.Delete("/api-keys/{id}", handler.RevokeAPIKey(apiKeySvc))
        })

        r.Group(func(r chi.Router) {
            r.Use(middleware.JWTAuth(s.verifier))

            r.Post("/consent", handler.RecordConsent(consentSvc))
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
        s.logger.Info().
            Str("addr", srv.Addr).
            Str("version", Version).
            Str("key_id", s.cfg.JWTSigningKeyID).
            Msg("auth-service starting")
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
