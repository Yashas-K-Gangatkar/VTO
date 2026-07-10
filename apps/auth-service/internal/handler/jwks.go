package handler

import (
    "encoding/json"
    "net/http"

    "github.com/vto/auth-service/internal/jwt"
)

func JWKS(verifier *jwt.Verifier) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        jwks := jwt.ToJWKS(verifier.PublicKey(), verifier.KeyID())

        w.Header().Set("Content-Type", "application/json")
        w.Header().Set("Cache-Control", "public, max-age=300")
        _ = json.NewEncoder(w).Encode(jwks)
    }
}
