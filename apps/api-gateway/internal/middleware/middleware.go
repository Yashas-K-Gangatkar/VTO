// Package middleware holds HTTP middleware for the API Gateway.
package middleware

import (
	"context"
	"net/http"
	"strconv"
	"time"

	"github.com/redis/go-redis/v9"
	"github.com/rs/zerolog"
)

// ctxKey is the type for context keys in this package.
type ctxKey int

const (
	ctxKeyRequestID ctxKey = iota
)

// RequestID injects a request ID into the context (uses X-Request-Id if present, else generates).
func RequestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		reqID := r.Header.Get("X-Request-Id")
		if reqID == "" {
			reqID = generateID()
		}
		w.Header().Set("X-Request-Id", reqID)
		ctx := context.WithValue(r.Context(), ctxKeyRequestID, reqID)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// Logger logs each request.
func Logger(logger zerolog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			start := time.Now()
			ww := &statusWriter{ResponseWriter: w, status: http.StatusOK}
			next.ServeHTTP(ww, r)

			logger.Info().
				Str("method", r.Method).
				Str("path", r.URL.Path).
				Int("status", ww.status).
				Dur("latency", time.Since(start)).
				Str("request_id", r.Header.Get("X-Request-Id")).
				Str("remote_addr", r.RemoteAddr).
				Msg("request")
		})
	}
}

// Recoverer recovers from panics, logs them, returns 500.
func Recoverer(logger zerolog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			defer func() {
				if rvr := recover(); rvr != nil {
					logger.Error().
						Interface("panic", rvr).
						Str("request_id", r.Header.Get("X-Request-Id")).
						Str("path", r.URL.Path).
						Msg("panic recovered")
					http.Error(w, `{"type":"about:blank","title":"Internal server error","status":500}`, http.StatusInternalServerError)
				}
			}()
			next.ServeHTTP(w, r)
		})
	}
}

// RateLimiter limits requests per-IP using a Redis sliding window.
type RateLimiter struct {
	rdb    *redis.Client
	limit  int
	window time.Duration
}

// NewRateLimiter creates a new RateLimiter.
func NewRateLimiter(rdb *redis.Client, limitPerMinute int) *RateLimiter {
	return &RateLimiter{
		rdb:    rdb,
		limit:  limitPerMinute,
		window: time.Minute,
	}
}

// Middleware returns an HTTP middleware that enforces rate limits.
func (rl *RateLimiter) Middleware() func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			key := "ratelimit:" + r.RemoteAddr + ":" + r.URL.Path
			ctx, cancel := context.WithTimeout(r.Context(), 100*time.Millisecond)
			defer cancel()

			count, err := rl.rdb.Incr(ctx, key).Result()
			if err == nil && count == 1 {
				_ = rl.rdb.Expire(ctx, key, rl.window).Err()
			}

			w.Header().Set("X-RateLimit-Limit", strconv.Itoa(rl.limit))
			w.Header().Set("X-RateLimit-Remaining", strconv.Itoa(max(0, rl.limit-int(count))))

			if count > int64(rl.limit) {
				w.Header().Set("Retry-After", "60")
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusTooManyRequests)
				_, _ = w.Write([]byte(`{
					"type": "https://docs.vto.example/errors/rate_limited",
					"title": "Too many requests",
					"status": 429,
					"detail": "Rate limit exceeded. Retry after the Retry-After header.",
					"instance": "` + r.Header.Get("X-Request-Id") + `"
				}`))
				return
			}

			next.ServeHTTP(w, r)
		})
	}
}

// statusWriter wraps http.ResponseWriter to capture status code.
type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(status int) {
	w.status = status
	w.ResponseWriter.WriteHeader(status)
}

// generateID returns a simple unique ID. Replace with UUID in production.
func generateID() string {
	return strconv.FormatInt(time.Now().UnixNano(), 36)
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}
