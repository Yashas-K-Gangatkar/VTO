package main

import (
    "context"
    "os"
    "os/signal"
    "syscall"
    "time"

    "github.com/rs/zerolog"
    "github.com/rs/zerolog/log"

    "github.com/vto/garment-service/internal/config"
    "github.com/vto/garment-service/internal/database"
    "github.com/vto/garment-service/internal/server"
    vtos3 "github.com/vto/garment-service/internal/s3"
)

func main() {
    zerolog.TimeFieldFormat = time.RFC3339Nano
    log.Logger = log.Output(os.Stdout).With().Str("service", "garment-service").Logger()

    cfg, err := config.Load()
    if err != nil {
        log.Fatal().Err(err).Msg("failed to load config")
    }

    level, err := zerolog.ParseLevel(cfg.LogLevel)
    if err != nil {
        level = zerolog.InfoLevel
    }
    zerolog.SetGlobalLevel(level)

    pool, err := database.New(cfg.DatabaseURL)
    if err != nil {
        log.Fatal().Err(err).Msg("failed to connect to Postgres")
    }
    defer pool.Close()
    log.Info().Msg("connected to Postgres")

    s3Client, err := vtos3.New(
        cfg.S3Endpoint, cfg.S3AccessKey, cfg.S3SecretKey,
        cfg.S3BucketGarments, cfg.S3Region, cfg.S3UsePathStyle,
    )
    if err != nil {
        log.Fatal().Err(err).Msg("failed to create S3 client")
    }
    log.Info().Str("bucket", cfg.S3BucketGarments).Msg("S3 client configured")

    srv := server.New(cfg, log.Logger, pool, s3Client)

    ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
    defer stop()

    if err := srv.Start(ctx); err != nil {
        log.Fatal().Err(err).Msg("server error")
    }
    log.Info().Msg("garment-service stopped")
}
