package config

import (
    "fmt"

    "github.com/kelseyhightower/envconfig"
)

type Config struct {
    Env      string `envconfig:"ENV" default:"dev"`
    LogLevel string `envconfig:"LOG_LEVEL" default:"info"`
    Port     int    `envconfig:"PORT" default:"8081"`

    DatabaseURL string `envconfig:"DATABASE_URL" default:"postgresql://vto:dev_password_change_me@postgres:5432/vto?sslmode=disable"`
    RedisURL    string `envconfig:"REDIS_URL" default:"redis://redis:6379"`

    JWTSigningKeyID   string `envconfig:"JWT_SIGNING_KEY_ID" default:"key-1"`
    JWTPrivateKeyPath string `envconfig:"JWT_PRIVATE_KEY_PATH" default:"/run/secrets/jwt-private.pem"`
    JWTPublicKeyPath  string `envconfig:"JWT_PUBLIC_KEY_PATH" default:"/run/secrets/jwt-public.pem"`
    JWTIssuer         string `envconfig:"JWT_ISSUER" default:"https://api.vto.example"`
    JWTAudience       string `envconfig:"JWT_AUDIENCE" default:"vto-platform"`

    DefaultTokenTTLSeconds int `envconfig:"DEFAULT_TOKEN_TTL_SECONDS" default:"3600"`

    RateLimitTokenMint int `envconfig:"RATE_LIMIT_TOKEN_MINT" default:"100"`
    RateLimitAPIKeyOps int `envconfig:"RATE_LIMIT_API_KEY_OPS" default:"20"`
}

func Load() (*Config, error) {
    var cfg Config
    if err := envconfig.Process("", &cfg); err != nil {
        return nil, fmt.Errorf("envconfig: %w", err)
    }
    return &cfg, nil
}
