package handler

import (
    "encoding/json"
    "errors"
    "net/http"
    "strconv"
    "time"

    "github.com/go-chi/chi/v5"
    "github.com/google/uuid"

    "github.com/vto/garment-service/internal/garment"
    "github.com/vto/garment-service/internal/middleware"
)

type SKUInput struct {
    SKU       string                 `json:"sku"`
    Name      string                 `json:"name"`
    Category  string                 `json:"category"`
    Gender    string                 `json:"gender"`
    Color     string                 `json:"color"`
    Fabric    string                 `json:"fabric"`
    ImageURLs []string               `json:"image_urls"`
    SizeChart map[string]interface{} `json:"size_chart"`
    Metadata  map[string]interface{} `json:"metadata"`
}

type SKUResponse struct {
    SKU                string                 `json:"sku"`
    Name               string                 `json:"name"`
    Category           string                 `json:"category"`
    Gender             string                 `json:"gender"`
    Color              string                 `json:"color"`
    Fabric             string                 `json:"fabric"`
    Metadata           map[string]interface{} `json:"metadata"`
    DigitizationStatus string                 `json:"digitization_status"`
}

func CreateSKU(svc *garment.Service) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        retailerID := middleware.RetailerIDFromContext(r.Context())
        if retailerID == "" {
            writeError(w, http.StatusUnauthorized, "missing_retailer", "Retailer ID not found")
            return
        }
        retailerUUID, err := uuid.Parse(retailerID)
        if err != nil {
            writeError(w, http.StatusInternalServerError, "invalid_retailer_id", "Invalid retailer ID")
            return
        }
        var req SKUInput
        if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
            writeError(w, http.StatusBadRequest, "invalid_json", "Request body must be valid JSON")
            return
        }
        if req.SKU == "" {
            writeValidationError(w, "sku", "sku is required")
            return
        }
        if req.Name == "" {
            writeValidationError(w, "name", "name is required")
            return
        }
        if len(req.ImageURLs) == 0 {
            writeValidationError(w, "image_urls", "at least one image_url is required")
            return
        }
        sku, rep, err := svc.CreateSKU(r.Context(), garment.CreateSKURequest{
            RetailerID: retailerUUID, SKU: req.SKU, Name: req.Name,
            Category: req.Category, Gender: req.Gender, Color: req.Color, Fabric: req.Fabric,
            ImageURLs: req.ImageURLs, SizeChart: req.SizeChart, Metadata: req.Metadata,
        })
        if err != nil {
            writeError(w, http.StatusInternalServerError, "create_failed", "Failed to create SKU: "+err.Error())
            return
        }
        w.Header().Set("Content-Type", "application/json")
        w.WriteHeader(http.StatusCreated)
        _ = json.NewEncoder(w).Encode(map[string]interface{}{
            "data": SKUResponse{
                SKU: sku.SKU, Name: sku.Name, Category: sku.Category,
                Gender: sku.Gender, Color: sku.Color, Fabric: sku.Fabric,
                Metadata: sku.Metadata, DigitizationStatus: string(rep.DigitizationStatus),
            },
            "meta": map[string]string{"request_id": middleware.RequestIDFromContext(r.Context())},
        })
    }
}

func GetSKU(svc *garment.Service) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        retailerID := middleware.RetailerIDFromContext(r.Context())
        if retailerID == "" {
            writeError(w, http.StatusUnauthorized, "missing_retailer", "Retailer ID not found")
            return
        }
        retailerUUID, err := uuid.Parse(retailerID)
        if err != nil {
            writeError(w, http.StatusInternalServerError, "invalid_retailer_id", "Invalid retailer ID")
            return
        }
        skuCode := chi.URLParam(r, "sku")
        sku, _, err := svc.GetSKU(r.Context(), retailerUUID, skuCode)
        if err != nil {
            if errors.Is(err, garment.ErrNotFound) {
                writeError(w, http.StatusNotFound, "not_found", "SKU not found")
                return
            }
            writeError(w, http.StatusInternalServerError, "get_failed", "Failed to get SKU")
            return
        }
        resp := SKUResponse{
            SKU: sku.SKU, Name: sku.Name, Category: sku.Category,
            Gender: sku.Gender, Color: sku.Color, Fabric: sku.Fabric,
            Metadata: sku.Metadata, DigitizationStatus: "pending",
        }
        w.Header().Set("Content-Type", "application/json")
        _ = json.NewEncoder(w).Encode(map[string]interface{}{
            "data": resp,
            "meta": map[string]string{"request_id": middleware.RequestIDFromContext(r.Context())},
        })
    }
}

func ListSKUs(svc *garment.Service) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        retailerID := middleware.RetailerIDFromContext(r.Context())
        if retailerID == "" {
            writeError(w, http.StatusUnauthorized, "missing_retailer", "Retailer ID not found")
            return
        }
        retailerUUID, err := uuid.Parse(retailerID)
        if err != nil {
            writeError(w, http.StatusInternalServerError, "invalid_retailer_id", "Invalid retailer ID")
            return
        }
        limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
        offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))
        skus, err := svc.ListSKUs(r.Context(), retailerUUID, limit, offset)
        if err != nil {
            writeError(w, http.StatusInternalServerError, "list_failed", "Failed to list SKUs")
            return
        }
        var resp []SKUResponse
        for _, s := range skus {
            resp = append(resp, SKUResponse{
                SKU: s.SKU, Name: s.Name, Category: s.Category,
                Gender: s.Gender, Color: s.Color, Fabric: s.Fabric,
                Metadata: s.Metadata, DigitizationStatus: "pending",
            })
        }
        if resp == nil { resp = []SKUResponse{} }
        w.Header().Set("Content-Type", "application/json")
        _ = json.NewEncoder(w).Encode(map[string]interface{}{
            "data": resp,
            "meta": map[string]string{"request_id": middleware.RequestIDFromContext(r.Context())},
        })
    }
}

func DeleteSKU(svc *garment.Service) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        retailerID := middleware.RetailerIDFromContext(r.Context())
        if retailerID == "" {
            writeError(w, http.StatusUnauthorized, "missing_retailer", "Retailer ID not found")
            return
        }
        retailerUUID, err := uuid.Parse(retailerID)
        if err != nil {
            writeError(w, http.StatusInternalServerError, "invalid_retailer_id", "Invalid retailer ID")
            return
        }
        skuCode := chi.URLParam(r, "sku")
        err = svc.DeleteSKU(r.Context(), retailerUUID, skuCode)
        if err != nil {
            if errors.Is(err, garment.ErrNotFound) {
                writeError(w, http.StatusNotFound, "not_found", "SKU not found")
                return
            }
            writeError(w, http.StatusInternalServerError, "delete_failed", "Failed to delete SKU")
            return
        }
        w.WriteHeader(http.StatusNoContent)
    }
}

var _ = time.Now
