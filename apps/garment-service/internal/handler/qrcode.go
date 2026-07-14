package handler

import (
    "encoding/json"
    "net/http"
    "strings"

    "github.com/go-chi/chi/v5"
    "github.com/google/uuid"

    "github.com/vto/garment-service/internal/middleware"
    "github.com/vto/garment-service/internal/qrcode"
)

type QRCodeRequest struct {
    SKU string `json:"sku"`
}

type QRCodeResponse struct {
    ID           string `json:"qr_id"`
    Payload      string `json:"payload"`
    PresignedURL string `json:"presigned_url"`
    ExpiresAt    string `json:"expires_at"`
}

func GenerateQRCode(svc *qrcode.QRCodeService) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        retailerID := middleware.RetailerIDFromContext(r.Context())
        if retailerID == "" {
            writeError(w, http.StatusUnauthorized, "missing_retailer", "Retailer ID not found")
            return
        }
        var req QRCodeRequest
        if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
            writeError(w, http.StatusBadRequest, "invalid_json", "Request body must be valid JSON")
            return
        }
        if req.SKU == "" {
            writeValidationError(w, "sku", "sku is required")
            return
        }
        _, err := uuid.Parse(retailerID)
        if err != nil {
            writeError(w, http.StatusInternalServerError, "invalid_retailer_id", "Invalid retailer ID")
            return
        }
        result, err := svc.Generate(r.Context(), retailerID, req.SKU)
        if err != nil {
            writeError(w, http.StatusInternalServerError, "qr_failed", "Failed to generate QR code: "+err.Error())
            return
        }
        w.Header().Set("Content-Type", "application/json")
        w.WriteHeader(http.StatusCreated)
        _ = json.NewEncoder(w).Encode(map[string]interface{}{
            "data": QRCodeResponse{
                ID:           result.ID,
                Payload:      result.Payload,
                PresignedURL: result.PresignedURL,
                ExpiresAt:    result.ExpiresAt.Format("2006-01-02T15:04:05Z07:00"),
            },
            "meta": map[string]string{"request_id": middleware.RequestIDFromContext(r.Context())},
        })
    }
}

func VerifyQRCode(svc *qrcode.QRCodeService) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        payloadStr := chi.URLParam(r, "payload")
        if payloadStr == "" {
            payloadStr = r.URL.Query().Get("p")
        }
        if payloadStr == "" {
            writeValidationError(w, "payload", "payload is required")
            return
        }
        if strings.HasPrefix(payloadStr, "vto://qr?p=") {
            payloadStr = strings.TrimPrefix(payloadStr, "vto://qr?p=")
        }
        payload, err := svc.Verify(payloadStr)
        if err != nil {
            writeError(w, http.StatusUnauthorized, "invalid_qr", "Invalid or expired QR code: "+err.Error())
            return
        }
        w.Header().Set("Content-Type", "application/json")
        _ = json.NewEncoder(w).Encode(map[string]interface{}{
            "data": map[string]interface{}{
                "qr_id":      payload.QRCodeID,
                "retailer_id": payload.RetailerID,
                "sku":        payload.SKU,
                "expires_at": payload.ExpiresAt,
            },
        })
    }
}
