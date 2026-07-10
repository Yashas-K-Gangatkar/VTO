// Package config holds environment-driven configuration for the API Gateway.
package config

import (
	"fmt"

	"github.com/kelseyhightower/envconfig"
)

// Config is the API Gateway configuration, loaded from environment variables.
type Config struct {
	Env      string `envconfig:"ENV" default:"dev"`
	LogLevel string `envconfig:"LOG_LEVEL" default:"info"`
	Port     int    `envconfig:"PORT" default:"8080"`

	// Upstream services
	AuthServiceURL     string `envconfig:"AUTH_SERVICE_URL" default:"http://auth-service:8081"`
	BodyServiceURL     string `envconfig:"BODY_SERVICE_URL" default:"http://body-service:8082"`
	GarmentServiceURL  string `envconfig:"GARMENT_SERVICE_URL" default:"http://garment-service:8083"`
	TryOnServiceURL    string `envconfig:"TRYON_SERVICE_URL" default:"http://tryon-service:8084"`
	AnalyticsServiceURL string `envconfig:"ANALYTICS_SERVICE_URL" default:"http://analytics-service:8085"`
	BillingServiceURL  string `envconfig:"BILLING_SERVICE_URL" default:"http://billing-service:8086"`
	WebhookServiceURL  string `envconfig:"WEBHOOK_SERVICE_URL" default:"http://webhook-service:8087"`

	// Redis (for rate limiting)
	RedisURL string `envconfig:"REDIS_URL" default:"redis://redis:6379"`

	// JWT verification
	JWKSURL string `envconfig:"JWKS_URL" default:"http://auth-service:8081/v1/.well-known/jwks.json"`

	// Rate limits (per minute)
	RateLimitDefault int `envconfig:"RATE_LIMIT_DEFAULT" default:"600"`
	RateLimitAuth    int `envconfig:"RATE_LIMIT_AUTH" default:"100"`
	RateLimitTryOn   int `envconfig:"RATE_LIMIT_TRYON" default:"60"`
	RateLimitEvents  int `envconfig:"RATE_LIMIT_EVENTS" default:"1000"`
}

// Load reads configuration from environment variables.
func Load() (*Config, error) {
	var cfg Config
	if err := envconfig.Process("", &cfg); err != nil {
		return nil, fmt.Errorf("envconfig: %w", err)
	}
	return &cfg, nil
}
