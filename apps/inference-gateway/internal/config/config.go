// Package config holds environment-driven configuration for inference-gateway.
package config

import (
        "fmt"

        "github.com/kelseyhightower/envconfig"
)

// Config is the inference-gateway configuration.
type Config struct {
        Env      string `envconfig:"ENV" default:"dev"`
        LogLevel string `envconfig:"LOG_LEVEL" default:"info"`
        Port     int    `envconfig:"PORT" default:"8090"`
}

// Load reads configuration from environment variables.
func Load() (*Config, error) {
        var cfg Config
        if err := envconfig.Process("", &cfg); err != nil {
                return nil, fmt.Errorf("envconfig: %w", err)
        }
        return &cfg, nil
}
