package middleware

import (
    "context"
    "encoding/json"
    "net/http"
    "strings"

    "github.com/google/uuid"

    "github.com/vto/auth-service/internal/apikey"
    "github.com/vto/auth-service/internal/jwt"
)

type ctxKey int

const (
    ctxKeyRetailerID ctxKey = iota
    ctxKeyShopperRef
    ctxKeyTokenID
    ctxKeyScopes
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

func APIKeyAuth(svc *apikey.Service) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            authHeader := r.Header.Get("Authorization")
            if authHeader == "" {
                writeError(w, http.StatusUnauthorized, "missing_authorization", "Authorization header required")
                return
            }

            parts := strings.SplitN(authHeader, " ", 2)
            if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
                writeError(w, http.StatusUnauthorized, "invalid_authorization", "Authorization must be 'Bearer <api-key>'")
                return
            }

            key := strings.TrimSpace(parts[1])
            if key == "" {
                writeError(w, http.StatusUnauthorized, "invalid_authorization", "API key is empty")
                return
            }

            apiKey, err := svc.Verify(r.Context(), key)
            if err != nil {
                writeError(w, http.StatusUnauthorized, "invalid_api_key", "Invalid or revoked API key")
                return
            }

            ctx := context.WithValue(r.Context(), ctxKeyRetailerID, apiKey.RetailerID.String())
            ctx = context.WithValue(ctx, ctxKeyScopes, apiKey.Scopes)
            next.ServeHTTP(w, r.WithContext(ctx))
        })
    }
}

func JWTAuth(verifier *jwt.Verifier) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            authHeader := r.Header.Get("Authorization")
            if authHeader == "" {
                writeError(w, http.StatusUnauthorized, "missing_authorization", "Authorization header required")
                return
            }

            parts := strings.SplitN(authHeader, " ", 2)
            if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
                writeError(w, http.StatusUnauthorized, "invalid_authorization", "Authorization must be 'Bearer <token>'")
                return
            }

            token := strings.TrimSpace(parts[1])
            claims, err := verifier.Verify(token)
            if err != nil {
                writeError(w, http.StatusUnauthorized, "invalid_token", "Invalid or expired token")
                return
            }

            ctx := context.WithValue(r.Context(), ctxKeyRetailerID, claims.RetailerID)
            ctx = context.WithValue(ctx, ctxKeyShopperRef, claims.ShopperRef)
            ctx = context.WithValue(ctx, ctxKeyTokenID, claims.ID)
            ctx = context.WithValue(ctx, ctxKeyScopes, claims.Scopes)
            next.ServeHTTP(w, r.WithContext(ctx))
        })
    }
}

func HasScope(ctx context.Context, scope string) bool {
    scopes, ok := ctx.Value(ctxKeyScopes).([]string)
    if !ok {
        return false
    }
    for _, s := range scopes {
        if s == scope {
            return true
        }
    }
    return false
}

func RetailerIDFromContext(ctx context.Context) string {
    if v, ok := ctx.Value(ctxKeyRetailerID).(string); ok {
        return v
    }
    return ""
}

func ShopperRefFromContext(ctx context.Context) string {
    if v, ok := ctx.Value(ctxKeyShopperRef).(string); ok {
        return v
    }
    return ""
}

func TokenIDFromContext(ctx context.Context) string {
    if v, ok := ctx.Value(ctxKeyTokenID).(string); ok {
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
        "errors": []map[string]string{
            {"code": code},
        },
    })
}
