package config

import (
    "fmt"

    "github.com/kelseyhightower/envconfig"
)

type Config struct {
    Env      string `envconfig:"ENV" default:"dev"`
    LogLevel string `envconfig:"LOG_LEVEL" default:"info"`
    Port     int    `envconfig:"PORT" default:"8084"`

    DatabaseURL string `envconfig:"DATABASE_URL" default:"postgresql://vto:dev_password_change_me@postgres:5432/vto?sslmode=disable"`
    RedisURL    string `envconfig:"REDIS_URL" default:"redis://redis:6379"`

    InferenceGatewayURL string `envconfig:"INFERENCE_GATEWAY_URL" default:"http://inference-gateway:8090"`
    AuthJWKSURL         string `envconfig:"AUTH_JWKS_URL" default:"http://auth-service:8081/v1/.well-known/jwks.json"

    CacheTTLHours int `envconfig:"CACHE_TTL_HOURS" default:"24"`
    ImageURLExpiryMinutes int `envconfig:"IMAGE_URL_EXPIRY_MINUTES" default:"1440"`
}

func Load() (*Config, error) {
    var cfg Config
    if err := envconfig.Process("", &cfg); err != nil {
        return nil, fmt.Errorf("envconfig: %w", err)
    }
    return &cfg, nil
}
