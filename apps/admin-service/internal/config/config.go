// Package config holds environment-driven configuration for admin-service.
package config

import (
        "fmt"

        "github.com/kelseyhightower/envconfig"
)

// Config is the admin-service configuration.
type Config struct {
        Env      string `envconfig:"ENV" default:"dev"`
        LogLevel string `envconfig:"LOG_LEVEL" default:"info"`
        Port     int    `envconfig:"PORT" default:"8089"`
        DatabaseURL string `envconfig:"DATABASE_URL" default:"postgresql://vto:dev_password_change_me@postgres:5432/vto?sslmode=disable"`
        RedisURL    string `envconfig:"REDIS_URL" default:"redis://redis:6379"`
}

// Load reads configuration from environment variables.
func Load() (*Config, error) {
        var cfg Config
        if err := envconfig.Process("", &cfg); err != nil {
                return nil, fmt.Errorf("envconfig: %w", err)
        }
        return &cfg, nil
}
