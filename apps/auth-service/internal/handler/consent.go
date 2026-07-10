package handler

import (
    "encoding/json"
    "net/http"
    "strings"

    "github.com/google/uuid"

    "github.com/vto/auth-service/internal/consent"
    "github.com/vto/auth-service/internal/middleware"
)

type ConsentRequest struct {
    ConsentType    string `json:"consent_type"`
    ConsentVersion string `json:"consent_version"`
    ConsentedAt    string `json:"consented_at"`
    Signature      string `json:"signature"`
}

type ConsentResponse struct {
    ID             string `json:"id"`
    ConsentType    string `json:"consent_type"`
    ConsentVersion string `json:"consent_version"`
    ConsentedAt    string `json:"consented_at"`
    Signature      string `json:"signature"`
}

func RecordConsent(svc *consent.Service) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        retailerID := middleware.RetailerIDFromContext(r.Context())
        shopperRef := middleware.ShopperRefFromContext(r.Context())
        if retailerID == "" || shopperRef == "" {
            writeError(w, http.StatusUnauthorized, "missing_identity", "Retailer ID or shopper ref not found in token")
            return
        }

        retailerUUID, err := uuid.Parse(retailerID)
        if err != nil {
            writeError(w, http.StatusInternalServerError, "invalid_retailer_id", "Invalid retailer ID in token")
            return
        }

        var req ConsentRequest
        if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
            writeError(w, http.StatusBadRequest, "invalid_json", "Request body must be valid JSON")
            return
        }

        if req.ConsentType == "" {
            writeValidationError(w, "consent_type", "consent_type is required")
            return
        }
        validTypes := map[string]bool{
            "body_scan":    true,
            "training_use": true,
        }
        if !validTypes[req.ConsentType] {
            writeValidationError(w, "consent_type", "invalid consent_type")
            return
        }
        if req.ConsentVersion == "" {
            writeValidationError(w, "consent_version", "consent_version is required")
            return
        }
        if req.Signature == "" {
            writeValidationError(w, "signature", "signature is required")
            return
        }

        ipAddress := r.RemoteAddr
        if forwarded := r.Header.Get("X-Forwarded-For"); forwarded != "" {
            ipAddress = strings.SplitN(forwarded, ",", 2)[0]
        }
        userAgent := r.Header.Get("User-Agent")

        record, err := svc.Record(r.Context(), retailerUUID, shopperRef, consent.ConsentType(req.ConsentType), req.ConsentVersion, req.Signature, ipAddress, userAgent)
        if err != nil {
            writeError(w, http.StatusInternalServerError, "consent_record_failed", "Failed to record consent")
            return
        }

        w.Header().Set("Content-Type", "application/json")
        w.WriteHeader(http.StatusCreated)
        _ = json.NewEncoder(w).Encode(map[string]interface{}{
            "data": ConsentResponse{
                ID:             record.ID.String(),
                ConsentType:    string(record.ConsentType),
                ConsentVersion: record.ConsentVersion,
                ConsentedAt:    record.ConsentedAt.Format("2006-01-02T15:04:05Z07:00"),
                Signature:      record.Signature,
            },
            "meta": map[string]string{
                "request_id": middleware.RequestIDFromContext(r.Context()),
            },
        })
    }
}
