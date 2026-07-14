package handler

import (
    "encoding/json"
    "errors"
    "net/http"
    "time"

    "github.com/go-chi/chi/v5"
    "github.com/google/uuid"

    "github.com/tryon-service/internal/middleware"
    "github.com/tryon-service/internal/tryon"
)

type CreateRequest struct {
    BodyProfileID string `json:"body_profile_id"`
    GarmentSKU    string `json:"garment_sku"`
    Size          string `json:"size"`
    View          string `json:"view"`
}

type CreateResponse struct {
    TryOnID              string `json:"tryon_id"`
    Status               string `json:"status"`
    EstimatedWaitSeconds int    `json:"estimated_wait_seconds"`
    PollURL              string `json:"poll_url"`
}

type TryOnResponse struct {
    TryOnID         string  `json:"tryon_id"`
    Status          string  `json:"status"`
    ImageURL        string  `json:"image_url,omitempty"`
    ImageExpiresAt  string  `json:"image_url_expires_at,omitempty"`
    ThumbnailURL    string  `json:"thumbnail_url,omitempty"`
    QualityScore    float64 `json:"quality_score,omitempty"`
    ModelVersion    string  `json:"model_version,omitempty"`
    RenderTimeMs    int     `json:"render_time_ms,omitempty"`
    Billed          bool    `json:"billed"`
    WillBillOn      string  `json:"will_bill_on"`
}

func CreateTryOn(svc *tryon.Service) http.HandlerFunc {
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

        var req CreateRequest
        if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
            writeError(w, http.StatusBadRequest, "invalid_json", "Request body must be valid JSON")
            return
        }

        if req.BodyProfileID == "" {
            writeValidationError(w, "body_profile_id", "body_profile_id is required")
            return
        }
        if req.GarmentSKU == "" {
            writeValidationError(w, "garment_sku", "garment_sku is required")
            return
        }

        bodyProfileID, err := uuid.Parse(req.BodyProfileID)
        if err != nil {
            writeValidationError(w, "body_profile_id", "invalid body_profile_id format")
            return
        }

        result, err := svc.Create(r.Context(), tryon.CreateRequest{
            RetailerID:    retailerUUID,
            ShopperRef:    shopperRef,
            BodyProfileID: bodyProfileID,
            GarmentSKU:    req.GarmentSKU,
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
            "data": CreateResponse{
                TryOnID:              result.ID.String(),
                Status:               string(result.Status),
                EstimatedWaitSeconds: 2,
                PollURL:              "/v1/tryons/" + result.ID.String(),
            },
            "meta": map[string]string{
                "request_id": middleware.RequestIDFromContext(r.Context()),
            },
        })
    }
}

func GetTryOn(svc *tryon.Service) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        retailerID := middleware.RetailerIDFromContext(r.Context())
        if retailerID == "" {
            writeError(w, http.StatusUnauthorized, "missing_retailer", "Retailer ID not found in token")
            return
        }

        retailerUUID, err := uuid.Parse(retailerID)
        if err != nil {
            writeError(w, http.StatusInternalServerError, "invalid_retailer_id", "Invalid retailer ID in token")
            return
        }

        tryonIDStr := chi.URLParam(r, "id")
        tryonID, err := uuid.Parse(tryonIDStr)
        if err != nil {
            writeValidationError(w, "id", "invalid try-on ID format")
            return
        }

        result, err := svc.Get(r.Context(), retailerUUID, tryonID)
        if err != nil {
            if errors.Is(err, tryon.ErrNotFound) {
                writeError(w, http.StatusNotFound, "not_found", "Try-on not found")
                return
            }
            writeError(w, http.StatusInternalServerError, "get_failed", "Failed to get try-on")
            return
        }

        resp := TryOnResponse{
            TryOnID:    result.ID.String(),
            Status:     string(result.Status),
            ImageURL:   result.ImageURL,
            ThumbnailURL: result.ThumbnailURL,
            Billed:     result.Billed,
            WillBillOn: "view",
        }
        if result.ImageExpiresAt != nil {
            resp.ImageExpiresAt = result.ImageExpiresAt.Format(time.RFC3339)
        }
        if result.QualityScore != nil {
            resp.QualityScore = *result.QualityScore
        }
        if result.ModelVersion != "" {
            resp.ModelVersion = result.ModelVersion
        }
        if result.RenderTimeMs != nil {
            resp.RenderTimeMs = *result.RenderTimeMs
        }

        w.Header().Set("Content-Type", "application/json")
        _ = json.NewEncoder(w).Encode(map[string]interface{}{
            "data": resp,
            "meta": map[string]string{
                "request_id": middleware.RequestIDFromContext(r.Context()),
            },
        })
    }
}

func MarkViewed(svc *tryon.Service) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        retailerID := middleware.RetailerIDFromContext(r.Context())
        if retailerID == "" {
            writeError(w, http.StatusUnauthorized, "missing_retailer", "Retailer ID not found in token")
            return
        }

        retailerUUID, err := uuid.Parse(retailerID)
        if err != nil {
            writeError(w, http.StatusInternalServerError, "invalid_retailer_id", "Invalid retailer ID in token")
            return
        }

        tryonIDStr := chi.URLParam(r, "id")
        tryonID, err := uuid.Parse(tryonIDStr)
        if err != nil {
            writeValidationError(w, "id", "invalid try-on ID format")
            return
        }

        _, err = svc.MarkViewed(r.Context(), retailerUUID, tryonID)
        if err != nil {
            writeError(w, http.StatusInternalServerError, "mark_viewed_failed", "Failed to mark try-on as viewed")
            return
        }

        w.WriteHeader(http.StatusNoContent)
    }
}
