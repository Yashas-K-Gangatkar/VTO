package config

import (
    "fmt"

    "github.com/kelseyhightower/envconfig"
)

type Config struct {
    Env      string `envconfig:"ENV" default:"dev"`
    LogLevel string `envconfig:"LOG_LEVEL" default:"info"`
    Port     int    `envconfig:"PORT" default:"8082"`

    DatabaseURL string `envconfig:"DATABASE_URL" default:"postgresql://vto:dev_password_change_me@postgres:5432/vto?sslmode=disable"`
    RedisURL    string `envconfig:"REDIS_URL" default:"redis://redis:6379"`

    S3Endpoint  string `envconfig:"S3_ENDPOINT" default:"http://minio:9000"`
    S3AccessKey string `envconfig:"S3_ACCESS_KEY" default:"vto_dev"`
    S3SecretKey string `envconfig:"S3_SECRET_KEY" default:"dev_password_change_me"`
    S3Bucket    string `envconfig:"S3_BUCKET" default:"vto-prod-body-profiles"`
    S3Region    string `envconfig:"S3_REGION" default:"us-east-1"`

    EncryptionKeyPath string `envconfig:"ENCRYPTION_KEY_PATH" default:"/run/secrets/body-encryption-key"`

    ProfileDefaultTTLDays int `envconfig:"PROFILE_DEFAULT_TTL_DAYS" default:"365"`
    DeletionSLAHours     int `envconfig:"DELETION_SLA_HOURS" default:"72"`
}

func Load() (*Config, error) {
    var cfg Config
    if err := envconfig.Process("", &cfg); err != nil {
        return nil, fmt.Errorf("envconfig: %w", err)
    }
    return &cfg, nil
}
