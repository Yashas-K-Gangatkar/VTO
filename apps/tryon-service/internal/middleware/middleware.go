package middleware

import (
    "context"
    "crypto/rsa"
    "encoding/base64"
    "encoding/json"
    "fmt"
    "math/big"
    "net/http"
    "strings"
    "sync"
    "time"

    "github.com/golang-jwt/jwt/v5"
    "github.com/google/uuid"
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
            reqID = uuid.New().String()
        }
        w.Header().Set("X-Request-Id", reqID)
        ctx := context.WithValue(r.Context(), ctxKeyRequestID, reqID)
        next.ServeHTTP(w, r.WithContext(ctx))
    })
}

type jwtClaims struct {
    RetailerID string   `json:"retailer_id"`
    ShopperRef string   `json:"shopper_ref"`
    Scopes     []string `json:"scopes"`
    jwt.RegisteredClaims
}

type jwksCache struct {
    keys      map[string]*rsa.PublicKey
    fetchedAt time.Time
}

var (
    jwksCacheMu   sync.RWMutex
    jwksCacheData *jwksCache
)

func fetchJWKS(jwksURL string) (map[string]*rsa.PublicKey, error) {
    jwksCacheMu.RLock()
    if jwksCacheData != nil && time.Since(jwksCacheData.fetchedAt) < 5*time.Minute {
        keys := jwksCacheData.keys
        jwksCacheMu.RUnlock()
        return keys, nil
    }
    jwksCacheMu.RUnlock()

    resp, err := http.Get(jwksURL)
    if err != nil {
        return nil, fmt.Errorf("fetch jwks: %w", err)
    }
    defer resp.Body.Close()

    var jwks struct {
        Keys []struct {
            KTY string `json:"kty"`
            KID string `json:"kid"`
            Use string `json:"use"`
            Alg string `json:"alg"`
            N   string `json:"n"`
            E   string `json:"e"`
        } `json:"keys"`
    }

    if err := json.NewDecoder(resp.Body).Decode(&jwks); err != nil {
        return nil, fmt.Errorf("decode jwks: %w", err)
    }

    keys := make(map[string]*rsa.PublicKey)
    for _, key := range jwks.Keys {
        if key.KTY != "RSA" {
            continue
        }
        nBytes, err := base64.RawURLEncoding.DecodeString(key.N)
        if err != nil {
            continue
        }
        eBytes, err := base64.RawURLEncoding.DecodeString(key.E)
        if err != nil {
            continue
        }
        n := new(big.Int).SetBytes(nBytes)
        e := 0
        for _, b := range eBytes {
            e = e<<8 + int(b)
        }
        keys[key.KID] = &rsa.PublicKey{N: n, E: e}
    }

    jwksCacheMu.Lock()
    jwksCacheData = &jwksCache{keys: keys, fetchedAt: time.Now()}
    jwksCacheMu.Unlock()

    return keys, nil
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
                writeError(w, http.StatusUnauthorized, "invalid_authorization", "Authorization must be Bearer token")
                return
            }
            tokenStr := strings.TrimSpace(parts[1])
            claims := &jwtClaims{}

            token, err := jwt.ParseWithClaims(tokenStr, claims, func(t *jwt.Token) (interface{}, error) {
                if _, ok := t.Method.(*jwt.SigningMethodRSA); !ok {
                    return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
                }
                kid, ok := t.Header["kid"].(string)
                if !ok {
                    return nil, fmt.Errorf("missing kid in token header")
                }
                keys, err := fetchJWKS(jwksURL)
                if err != nil {
                    return nil, fmt.Errorf("fetch jwks: %w", err)
                }
                key, ok := keys[kid]
                if !ok {
                    return nil, fmt.Errorf("key not found for kid: %s", kid)
                }
                return key, nil
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
