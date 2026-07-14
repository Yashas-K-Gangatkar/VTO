package middleware

import (
    "context"
    "crypto/sha256"
    "encoding/hex"
    "encoding/json"
    "fmt"
    "net/http"
    "strings"
    "time"

    "github.com/google/uuid"
    "github.com/jackc/pgx/v5"
    "github.com/jackc/pgx/v5/pgxpool"
)

type ctxKey int

const (
    ctxKeyRetailerID ctxKey = iota
    ctxKeyRequestID
)

func RequestID(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        reqID := r.Header.Get("X-Request-Id")
        if reqID == "" {
            reqID = uuid.New().String()
        }
        w.Header().Set("X-Request-Id", reqID)
        ctx := context.WithValue(r.Context(), ctxKeyRequestID, reqID)
        next.ServeHTTP(w, r.WithContext(ctx))
    })
}

func APIKeyAuth(pool *pgxpool.Pool) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            authHeader := r.Header.Get("Authorization")
            if authHeader == "" {
                writeError(w, http.StatusUnauthorized, "missing_authorization", "Authorization header required")
                return
            }
            parts := strings.SplitN(authHeader, " ", 2)
            if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
                writeError(w, http.StatusUnauthorized, "invalid_authorization", "Authorization must be Bearer <api-key>")
                return
            }
            key := strings.TrimSpace(parts[1])
            retailerID, err := verifyAPIKey(r.Context(), pool, key)
            if err != nil {
                writeError(w, http.StatusUnauthorized, "invalid_api_key", "Invalid or revoked API key")
                return
            }
            ctx := context.WithValue(r.Context(), ctxKeyRetailerID, retailerID)
            next.ServeHTTP(w, r.WithContext(ctx))
        })
    }
}

func verifyAPIKey(ctx context.Context, pool *pgxpool.Pool, key string) (string, error) {
    h := sha256.Sum256([]byte(key))
    hash := hex.EncodeToString(h[:])
    var retailerID string
    err := pool.QueryRow(ctx, `
        SELECT retailer_id::text FROM auth.api_keys
        WHERE key_hash = $1 AND revoked_at IS NULL
    `, hash).Scan(&retailerID)
    if err != nil {
        if err == pgx.ErrNoRows {
            return "", fmt.Errorf("invalid api key")
        }
        return "", fmt.Errorf("query api key: %w", err)
    }
    go func() {
        bgCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
        defer cancel()
        _, _ = pool.Exec(bgCtx, `UPDATE auth.api_keys SET last_used_at = NOW() WHERE key_hash = $1`, hash)
    }()
    return retailerID, nil
}

func RetailerIDFromContext(ctx context.Context) string {
    if v, ok := ctx.Value(ctxKeyRetailerID).(string); ok {
        return v
    }
    return ""
}

func RequestIDFromContext(ctx context.Context) string {
    if v, ok := ctx.Value(ctxKeyRequestID).(string); ok {
        return v
    }
    return ""
}

func writeError(w http.ResponseWriter, status int, code, detail string) {
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(status)
    _ = json.NewEncoder(w).Encode(map[string]interface{}{
        "type":   "https://docs.vto.example/errors/" + code,
        "title":  http.StatusText(status),
        "status": status,
        "detail": detail,
        "errors": []map[string]string{{"code": code}},
    })
}
