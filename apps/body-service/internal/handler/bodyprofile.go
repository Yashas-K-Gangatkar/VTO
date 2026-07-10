package handler

import (
    "encoding/json"
    "errors"
    "io"
    "net/http"
    "time"

    "github.com/go-chi/chi/v5"
    "github.com/google/uuid"

    "github.com/vto/body-service/internal/bodyprofile"
    "github.com/vto/body-service/internal/middleware"
)

type BodyProfileResponse struct {
    ID           string             `json:"id"`
    Status       string             `json:"status"`
    Measurements map[string]float64 `json:"measurements"`
    ScanDevice   string             `json:"scan_device"`
    QualityScore float64            `json:"quality_score"`
    CreatedAt    string             `json:"created_at"`
    ExpiresAt    string             `json:"expires_at"`
}

type CreateResponse struct {
    Data BodyProfileResponse `json:"data"`
    Meta map[string]string   `json:"meta"`
}

func CreateBodyProfile(svc *bodyprofile.Service) http.HandlerFunc {
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

        if err := r.ParseMultipartForm(50 << 20); err != nil {
            writeError(w, http.StatusBadRequest, "invalid_form", "Request must be multipart/form-data with max 50MB")
            return
        }

        file, _, err := r.FormFile("scan_data")
        if err != nil {
            writeValidationError(w, "scan_data", "scan_data file is required")
            return
        }
        defer file.Close()

        scanData, err := io.ReadAll(file)
        if err != nil {
            writeError(w, http.StatusInternalServerError, "read_failed", "Failed to read scan data")
            return
        }

        metadataStr := r.FormValue("metadata")
        if metadataStr == "" {
            writeValidationError(w, "metadata", "metadata is required")
            return
        }

        var metadata struct {
            ScanDevice   string             `json:"scan_device"`
            QualityScore float64            `json:"scan_quality_score"`
            Measurements map[string]float64 `json:"measurements"`
        }
        if err := json.Unmarshal([]byte(metadataStr), &metadata); err != nil {
            writeValidationError(w, "metadata", "metadata must be valid JSON")
            return
        }

        profile, err := svc.Create(r.Context(), bodyprofile.CreateRequest{
            RetailerID:   retailerUUID,
            ShopperRef:   shopperRef,
            ScanData:     scanData,
            ScanDevice:   metadata.ScanDevice,
            QualityScore: metadata.QualityScore,
            Measurements: metadata.Measurements,
            TTLDays:      0,
        })
        if err != nil {
            writeError(w, http.StatusInternalServerError, "create_failed", "Failed to create body profile: "+err.Error())
            return
        }

        w.Header().Set("Content-Type", "application/json")
        w.WriteHeader(http.StatusCreated)
        _ = json.NewEncoder(w).Encode(CreateResponse{
            Data: BodyProfileResponse{
                ID:           profile.ID.String(),
                Status:       profile.Status,
                Measurements: profile.Measurements,
                ScanDevice:   profile.ScanDevice,
                QualityScore: profile.QualityScore,
                CreatedAt:    profile.CreatedAt.Format(time.RFC3339),
                ExpiresAt:    profile.ExpiresAt.Format(time.RFC3339),
            },
            Meta: map[string]string{
                "request_id": middleware.RequestIDFromContext(r.Context()),
            },
        })
    }
}

func GetBodyProfile(svc *bodyprofile.Service) http.HandlerFunc {
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

        profileIDStr := chi.URLParam(r, "id")
        profileID, err := uuid.Parse(profileIDStr)
        if err != nil {
            writeValidationError(w, "id", "invalid profile ID format")
            return
        }

        profile, err := svc.Get(r.Context(), retailerUUID, profileID)
        if err != nil {
            if errors.Is(err, bodyprofile.ErrNotFound) {
                writeError(w, http.StatusNotFound, "not_found", "Body profile not found")
                return
            }
            if errors.Is(err, bodyprofile.ErrExpired) {
                writeError(w, http.StatusGone, "expired", "Body profile has expired")
                return
            }
            writeError(w, http.StatusInternalServerError, "get_failed", "Failed to get body profile")
            return
        }

        w.Header().Set("Content-Type", "application/json")
        _ = json.NewEncoder(w).Encode(map[string]interface{}{
            "data": BodyProfileResponse{
                ID:           profile.ID.String(),
                Status:       profile.Status,
                Measurements: profile.Measurements,
                ScanDevice:   profile.ScanDevice,
                QualityScore: profile.QualityScore,
                CreatedAt:    profile.CreatedAt.Format(time.RFC3339),
                ExpiresAt:    profile.ExpiresAt.Format(time.RFC3339),
            },
            "meta": map[string]string{
                "request_id": middleware.RequestIDFromContext(r.Context()),
            },
        })
    }
}

func DeleteBodyProfile(svc *bodyprofile.Service) http.HandlerFunc {
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

        profileIDStr := chi.URLParam(r, "id")
        profileID, err := uuid.Parse(profileIDStr)
        if err != nil {
            writeValidationError(w, "id", "invalid profile ID format")
            return
        }

        err = svc.Delete(r.Context(), retailerUUID, profileID)
        if err != nil {
            if errors.Is(err, bodyprofile.ErrNotFound) {
                writeError(w, http.StatusNotFound, "not_found", "Body profile not found")
                return
            }
            writeError(w, http.StatusInternalServerError, "delete_failed", "Failed to delete body profile")
            return
        }

        w.WriteHeader(http.StatusNoContent)
    }
}
