package config

import (
    "fmt"

    "github.com/kelseyhightower/envconfig"
)

type Config struct {
    Env      string `envconfig:"ENV" default:"dev"`
    LogLevel string `envconfig:"LOG_LEVEL" default:"info"`
    Port     int    `envconfig:"PORT" default:"8083"`

    DatabaseURL string `envconfig:"DATABASE_URL" default:"postgresql://vto:dev_password_change_me@postgres:5432/vto?sslmode=disable"`
    RedisURL    string `envconfig:"REDIS_URL" default:"redis://redis:6379"`

    S3Endpoint        string `envconfig:"S3_ENDPOINT" default:"http://minio:9000"`
    S3AccessKey       string `envconfig:"S3_ACCESS_KEY" default:"vto_dev"`
    S3SecretKey       string `envconfig:"S3_SECRET_KEY" default:"dev_password_change_me"`
    S3Region          string `envconfig:"S3_REGION" default:"us-east-1"`
    S3BucketGarments  string `envconfig:"S3_BUCKET_GARMENTS" default:"vto-prod-garment-images"`
    S3UsePathStyle    bool   `envconfig:"S3_USE_PATH_STYLE" default:"true"`

    AuthJWKSURL string `envconfig:"AUTH_JWKS_URL" default:"http://auth-service:8081/v1/.well-known/jwks.json"`

    QRCodeTokenSecret   string `envconfig:"QR_CODE_TOKEN_SECRET" default:"dev-qr-secret-change-in-prod"`
    QRCodeTokenTTLHours int    `envconfig:"QR_CODE_TOKEN_TTL_HOURS" default:"17520"`
}

func Load() (*Config, error) {
    var cfg Config
    if err := envconfig.Process("", &cfg); err != nil {
        return nil, fmt.Errorf("envconfig: %w", err)
    }
    return &cfg, nil
}
