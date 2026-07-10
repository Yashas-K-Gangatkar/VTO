package main

import (
    "context"
    "os"
    "os/signal"
    "syscall"
    "time"

    "github.com/rs/zerolog"
    "github.com/rs/zerolog/log"

    "github.com/tryon-service/internal/cache"
    "github.com/tryon-service/internal/config"
    "github.com/tryon-service/internal/database"
    "github.com/tryon-service/internal/server"
)

func main() {
    zerolog.TimeFieldFormat = time.RFC3339Nano
    log.Logger = log.Output(os.Stdout).With().Str("service", "tryon-service").Logger()

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

    cacheClient, err := cache.New(cfg.RedisURL)
    if err != nil {
        log.Fatal().Err(err).Msg("failed to connect to Redis")
    }
    defer cacheClient.Close()
    log.Info().Msg("connected to Redis")

    srv := server.New(cfg, log.Logger, pool, cacheClient)

    ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
    defer stop()

    if err := srv.Start(ctx); err != nil {
        log.Fatal().Err(err).Msg("server error")
    }

    log.Info().Msg("tryon-service stopped")
}
