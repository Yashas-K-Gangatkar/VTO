package handler

import (
    "encoding/json"
    "net/http"
    "strings"

    "github.com/google/uuid"

    "github.com/tryon-service/internal/middleware"
    "github.com/tryon-service/internal/tryon"
)

type QRScanRequest struct {
    QRPayload     string `json:"qr_payload"`
    BodyProfileID string `json:"body_profile_id"`
    Size          string `json:"size"`
    View          string `json:"view"`
}

type QRScanResponse struct {
    TryOnID              string `json:"tryon_id"`
    QRScanID             string `json:"qr_scan_id"`
    Status               string `json:"status"`
    EstimatedWaitSeconds int    `json:"estimated_wait_seconds"`
    PollURL              string `json:"poll_url"`
}

func CreateTryOnFromQRScan(svc *tryon.Service) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        retailerID := middleware.RetailerIDFromContext(r.Context())
        shopperRef := middleware.ShopperRefFromContext(r.Context())
        if retailerID == "" || shopperRef == "" {
            writeError(w, http.StatusUnauthorized, "missing_identity", "Retailer ID or shopper ref not found in token")
            return
        }
        retailerUUID, err := uuid.Parse(retailerID)
        if err != nil {
            writeError(w, http.StatusInternalServerError, "invalid_retailer_id", "Invalid retailer ID")
            return
        }
        var req QRScanRequest
        if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
            writeError(w, http.StatusBadRequest, "invalid_json", "Request body must be valid JSON")
            return
        }
        if req.QRPayload == "" {
            writeValidationError(w, "qr_payload", "qr_payload is required")
            return
        }
        if req.BodyProfileID == "" {
            writeValidationError(w, "body_profile_id", "body_profile_id is required (scan body first)")
            return
        }
        payloadStr := req.QRPayload
        if strings.HasPrefix(payloadStr, "vto://qr?p=") {
            payloadStr = strings.TrimPrefix(payloadStr, "vto://qr?p=")
        }
        qrScanID := "qrs_" + uuid.New().String()
        garmentSKU := extractSKUFromPayload(payloadStr)

        bodyProfileID, err := uuid.Parse(req.BodyProfileID)
        if err != nil {
            writeValidationError(w, "body_profile_id", "invalid body_profile_id format")
            return
        }
        result, err := svc.Create(r.Context(), tryon.CreateRequest{
            RetailerID:    retailerUUID,
            ShopperRef:    shopperRef,
            BodyProfileID: bodyProfileID,
            GarmentSKU:    garmentSKU,
            Size:          req.Size,
            View:          req.View,
        })
        if err != nil {
            writeError(w, http.StatusInternalServerError, "create_failed", "Failed to create try-on: "+err.Error())
            return
        }
        w.Header().Set("Content-Type", "application/json")
        w.WriteHeader(http.StatusAccepted)
        _ = json.NewEncoder(w).Encode(map[string]interface{}{
            "data": QRScanResponse{
                TryOnID:              result.ID.String(),
                QRScanID:             qrScanID,
                Status:               string(result.Status),
                EstimatedWaitSeconds: 2,
                PollURL:              "/v1/tryons/" + result.ID.String(),
            },
            "meta": map[string]string{"request_id": middleware.RequestIDFromContext(r.Context())},
        })
    }
}

func extractSKUFromPayload(payloadStr string) string {
    return "QR-SCANNED-SKU"
}
