// Package handler holds HTTP handlers for dashboard-api.
package handler

import (
        "encoding/json"
        "net/http"
        "runtime"
        "time"
)

// HealthResponse is the /health response.
type HealthResponse struct {
        Status    string    `json:"status"`
        Version   string    `json:"version"`
        Timestamp time.Time `json:"timestamp"`
        GoVersion string    `json:"go_version"`
}

// Health handles GET /health.
func Health(version string) http.HandlerFunc {
        return func(w http.ResponseWriter, r *http.Request) {
                w.Header().Set("Content-Type", "application/json")
                _ = json.NewEncoder(w).Encode(HealthResponse{
                        Status:    "ok",
                        Version:   version,
                        Timestamp: time.Now().UTC(),
                        GoVersion: runtime.Version(),
                })
        }
}
