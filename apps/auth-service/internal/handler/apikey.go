package handler

import (
    "encoding/json"
    "errors"
    "net/http"
    "time"

    "github.com/go-chi/chi/v5"
    "github.com/google/uuid"

    "github.com/vto/auth-service/internal/apikey"
    "github.com/vto/auth-service/internal/middleware"
)

type APIKeyCreateRequest struct {
    Name   string   `json:"name"`
    Scopes []string `json:"scopes"`
}

type APIKeyResponse struct {
    ID         uuid.UUID  `json:"id"`
    Name       string     `json:"name"`
    KeyPrefix  string     `json:"key_prefix"`
    Scopes     []string   `json:"scopes"`
    LastUsedAt *time.Time `json:"last_used_at,omitempty"`
    CreatedAt  time.Time  `json:"created_at"`
}

type FullAPIKeyResponse struct {
    APIKeyResponse
    Key string `json:"key"`
}

func CreateAPIKey(svc *apikey.Service) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        retailerID := middleware.RetailerIDFromContext(r.Context())
        if retailerID == "" {
            writeError(w, http.StatusUnauthorized, "missing_retailer", "Retailer ID not found in context")
            return
        }

        retailerUUID, err := uuid.Parse(retailerID)
        if err != nil {
            writeError(w, http.StatusInternalServerError, "invalid_retailer_id", "Invalid retailer ID in context")
            return
        }

        var req APIKeyCreateRequest
        if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
            writeError(w, http.StatusBadRequest, "invalid_json", "Request body must be valid JSON")
            return
        }

        if req.Name == "" {
            writeValidationError(w, "name", "name is required")
            return
        }
        if len(req.Name) > 100 {
            writeValidationError(w, "name", "name must be 100 characters or fewer")
            return
        }

        fullKey, err := svc.Create(r.Context(), retailerUUID, req.Name, req.Scopes, nil)
        if err != nil {
            writeError(w, http.StatusInternalServerError, "create_failed", "Failed to create API key")
            return
        }

        w.Header().Set("Content-Type", "application/json")
        w.WriteHeader(http.StatusCreated)
        _ = json.NewEncoder(w).Encode(map[string]interface{}{
            "data": FullAPIKeyResponse{
                APIKeyResponse: APIKeyResponse{
                    ID:        fullKey.ID,
                    Name:      fullKey.Name,
                    KeyPrefix: fullKey.KeyPrefix,
                    Scopes:    fullKey.Scopes,
                    CreatedAt: fullKey.CreatedAt,
                },
                Key: fullKey.Key,
            },
            "meta": map[string]string{
                "request_id": middleware.RequestIDFromContext(r.Context()),
            },
        })
    }
}

func ListAPIKeys(svc *apikey.Service) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        retailerID := middleware.RetailerIDFromContext(r.Context())
        if retailerID == "" {
            writeError(w, http.StatusUnauthorized, "missing_retailer", "Retailer ID not found in context")
            return
        }

        retailerUUID, err := uuid.Parse(retailerID)
        if err != nil {
            writeError(w, http.StatusInternalServerError, "invalid_retailer_id", "Invalid retailer ID in context")
            return
        }

        keys, err := svc.List(r.Context(), retailerUUID)
        if err != nil {
            writeError(w, http.StatusInternalServerError, "list_failed", "Failed to list API keys")
            return
        }

        var resp []APIKeyResponse
        for _, k := range keys {
            resp = append(resp, APIKeyResponse{
                ID:         k.ID,
                Name:       k.Name,
                KeyPrefix:  k.KeyPrefix,
                Scopes:     k.Scopes,
                LastUsedAt: k.LastUsedAt,
                CreatedAt:  k.CreatedAt,
            })
        }
        if resp == nil {
            resp = []APIKeyResponse{}
        }

        w.Header().Set("Content-Type", "application/json")
        _ = json.NewEncoder(w).Encode(map[string]interface{}{
            "data": resp,
            "meta": map[string]interface{}{
                "request_id": middleware.RequestIDFromContext(r.Context()),
            },
        })
    }
}

func RevokeAPIKey(svc *apikey.Service) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        retailerID := middleware.RetailerIDFromContext(r.Context())
        if retailerID == "" {
            writeError(w, http.StatusUnauthorized, "missing_retailer", "Retailer ID not found in context")
            return
        }

        retailerUUID, err := uuid.Parse(retailerID)
        if err != nil {
            writeError(w, http.StatusInternalServerError, "invalid_retailer_id", "Invalid retailer ID in context")
            return
        }

        keyIDStr := chi.URLParam(r, "id")
        keyID, err := uuid.Parse(keyIDStr)
        if err != nil {
            writeValidationError(w, "id", "invalid API key ID format")
            return
        }

        err = svc.Revoke(r.Context(), retailerUUID, keyID, "revoked via API")
        if err != nil {
            if errors.Is(err, apikey.ErrNotFound) {
                writeError(w, http.StatusNotFound, "not_found", "API key not found")
                return
            }
            writeError(w, http.StatusInternalServerError, "revoke_failed", "Failed to revoke API key")
            return
        }

        w.WriteHeader(http.StatusNoContent)
    }
}
