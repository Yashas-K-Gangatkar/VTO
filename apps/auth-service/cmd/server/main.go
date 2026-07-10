package main

import (
    "context"
    "os"
    "os/signal"
    "syscall"
    "time"

    "github.com/redis/go-redis/v9"
    "github.com/rs/zerolog"
    "github.com/rs/zerolog/log"

    "github.com/vto/auth-service/internal/config"
    "github.com/vto/auth-service/internal/database"
    "github.com/vto/auth-service/internal/server"
)

func main() {
    zerolog.TimeFieldFormat = time.RFC3339Nano
    log.Logger = log.Output(os.Stdout).With().Str("service", "auth-service").Logger()

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
        log.Fatal().Err(err).Str("url", cfg.DatabaseURL).Msg("failed to connect to Postgres")
    }
    defer pool.Close()
    log.Info().Msg("connected to Postgres")

    opt, err := redis.ParseURL(cfg.RedisURL)
    if err != nil {
        log.Fatal().Err(err).Str("url", cfg.RedisURL).Msg("invalid Redis URL")
    }
    rdb := redis.NewClient(opt)

    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()
    if err := rdb.Ping(ctx).Err(); err != nil {
        log.Fatal().Err(err).Msg("failed to connect to Redis")
    }
    defer rdb.Close()
    log.Info().Msg("connected to Redis")

    srv, err := server.New(cfg, log.Logger, pool, rdb)
    if err != nil {
        log.Fatal().Err(err).Msg("failed to create server")
    }

    ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
    defer stop()

    if err := srv.Start(ctx); err != nil {
        log.Fatal().Err(err).Msg("server error")
    }

    log.Info().Msg("auth-service stopped")
}
