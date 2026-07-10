package handler

import (
    "encoding/json"
    "errors"
    "net/http"

    "github.com/vto/auth-service/internal/middleware"
    "github.com/vto/auth-service/internal/token"
)

type TokenRequest struct {
    ShopperID  string   `json:"shopper_id"`
    Scopes     []string `json:"scopes"`
    TTLSeconds int      `json:"ttl_seconds"`
}

type TokenResponse struct {
    AccessToken    string `json:"access_token"`
    TokenType      string `json:"token_type"`
    ExpiresIn      int    `json:"expires_in"`
    ShopperTokenID string `json:"shopper_token_id"`
}

func MintToken(svc *token.Service, defaultTTL int) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        retailerID := middleware.RetailerIDFromContext(r.Context())
        if retailerID == "" {
            writeError(w, http.StatusUnauthorized, "missing_retailer", "Retailer ID not found in context")
            return
        }

        var req TokenRequest
        if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
            writeError(w, http.StatusBadRequest, "invalid_json", "Request body must be valid JSON")
            return
        }

        if req.ShopperID == "" {
            writeValidationError(w, "shopper_id", "shopper_id is required")
            return
        }
        if len(req.Scopes) == 0 {
            writeValidationError(w, "scopes", "at least one scope is required")
            return
        }

        validScopes := map[string]bool{
            "body_scan":   true,
            "tryon":       true,
            "events":      true,
            "attribution": true,
        }
        for _, s := range req.Scopes {
            if !validScopes[s] {
                writeValidationError(w, "scopes", "invalid scope: "+s)
                return
            }
        }

        ttl := req.TTLSeconds
        if ttl <= 0 {
            ttl = defaultTTL
        }

        ipAddress := r.RemoteAddr
        if forwarded := r.Header.Get("X-Forwarded-For"); forwarded != "" {
            ipAddress = forwarded
        }

        result, err := svc.Mint(r.Context(), token.MintRequest{
            RetailerID: retailerID,
            ShopperRef: req.ShopperID,
            Scopes:     req.Scopes,
            TTLSeconds: ttl,
            IPAddress:  ipAddress,
        })
        if err != nil {
            writeError(w, http.StatusInternalServerError, "mint_failed", "Failed to mint token: "+err.Error())
            return
        }

        w.Header().Set("Content-Type", "application/json")
        w.WriteHeader(http.StatusOK)
        _ = json.NewEncoder(w).Encode(map[string]interface{}{
            "data": TokenResponse{
                AccessToken:    result.AccessToken,
                TokenType:      result.TokenType,
                ExpiresIn:      result.ExpiresIn,
                ShopperTokenID: result.ShopperTokenID,
            },
            "meta": map[string]string{
                "request_id": middleware.RequestIDFromContext(r.Context()),
            },
        })
    }
}

type RevokeTokenRequest struct {
    ShopperTokenID string `json:"shopper_token_id"`
}

func RevokeToken(svc *token.Service) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        retailerID := middleware.RetailerIDFromContext(r.Context())
        if retailerID == "" {
            writeError(w, http.StatusUnauthorized, "missing_retailer", "Retailer ID not found in context")
            return
        }

        var req RevokeTokenRequest
        if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
            writeError(w, http.StatusBadRequest, "invalid_json", "Request body must be valid JSON")
            return
        }

        if req.ShopperTokenID == "" {
            writeValidationError(w, "shopper_token_id", "shopper_token_id is required")
            return
        }

        err := svc.Revoke(r.Context(), retailerID, req.ShopperTokenID)
        if err != nil {
            if errors.Is(err, token.ErrInvalidToken) {
                writeError(w, http.StatusNotFound, "token_not_found", "Token not found or already revoked")
                return
            }
            writeError(w, http.StatusInternalServerError, "revoke_failed", "Failed to revoke token")
            return
        }

        w.WriteHeader(http.StatusNoContent)
    }
}
