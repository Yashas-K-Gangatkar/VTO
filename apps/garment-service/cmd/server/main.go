// Package main is the entry point for garment-service.
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
        "github.com/vto/garment-service/internal/server"
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

        srv := server.New(cfg, log.Logger)

        ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
        defer stop()

        if err := srv.Start(ctx); err != nil {
                log.Fatal().Err(err).Msg("server error")
        }

        log.Info().Msg("garment-service stopped")
}
