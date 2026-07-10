package middleware

import (
    "context"
    "encoding/json"
    "net/http"
    "strings"

    "github.com/golang-jwt/jwt/v5"
)

type ctxKey int

const (
    ctxKeyRetailerID ctxKey = iota
    ctxKeyShopperRef
    ctxKeyTokenID
    ctxKeyRequestID
)

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

type Claims struct {
    RetailerID string   `json:"retailer_id"`
    ShopperRef string   `json:"shopper_ref"`
    Scopes     []string `json:"scopes"`
    jwt.RegisteredClaims
}

func JWTAuth(jwksURL string) func(http.Handler) http.Handler {
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

            tokenStr := strings.TrimSpace(parts[1])
            claims := &Claims{}

            token, err := jwt.ParseWithClaims(tokenStr, claims, func(t *jwt.Token) (interface{}, error) {
                if _, ok := t.Method.(*jwt.SigningMethodRSA); !ok {
                    return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
                }
                return getPublicKey(jwksURL, t.Header["kid"].(string))
            })

            if err != nil || !token.Valid {
                writeError(w, http.StatusUnauthorized, "invalid_token", "Invalid or expired token")
                return
            }

            ctx := context.WithValue(r.Context(), ctxKeyRetailerID, claims.RetailerID)
            ctx = context.WithValue(ctx, ctxKeyShopperRef, claims.ShopperRef)
            ctx = context.WithValue(ctx, ctxKeyTokenID, claims.ID)
            next.ServeHTTP(w, r.WithContext(ctx))
        })
    }
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

func generateID() string {
    return "req-" + fmt.Sprintf("%d", time.Now().UnixNano())
}
