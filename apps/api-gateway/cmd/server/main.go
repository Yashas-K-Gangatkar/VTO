// Package main is the entry point for the API Gateway.
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

	"github.com/vto/api-gateway/internal/config"
	"github.com/vto/api-gateway/internal/server"
)

func main() {
	zerolog.TimeFieldFormat = time.RFC3339Nano
	log.Logger = log.Output(os.Stdout).With().Str("service", "api-gateway").Logger()

	cfg, err := config.Load()
	if err != nil {
		log.Fatal().Err(err).Msg("failed to load config")
	}

	level, err := zerolog.ParseLevel(cfg.LogLevel)
	if err != nil {
		level = zerolog.InfoLevel
	}
	zerolog.SetGlobalLevel(level)

	// Parse Redis URL
	opt, err := redis.ParseURL(cfg.RedisURL)
	if err != nil {
		log.Fatal().Err(err).Str("url", cfg.RedisURL).Msg("invalid Redis URL")
	}
	rdb := redis.NewClient(opt)

	// Ping Redis
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := rdb.Ping(ctx).Err(); err != nil {
		log.Fatal().Err(err).Msg("failed to connect to Redis")
	}
	log.Info().Str("url", cfg.RedisURL).Msg("connected to Redis")

	srv, err := server.New(cfg, log.Logger, rdb)
	if err != nil {
		log.Fatal().Err(err).Msg("failed to create server")
	}

	// Graceful shutdown
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	if err := srv.Start(ctx); err != nil {
		log.Fatal().Err(err).Msg("server error")
	}

	log.Info().Msg("api-gateway stopped")
}
