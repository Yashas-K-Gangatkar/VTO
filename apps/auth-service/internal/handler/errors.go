package handler

import (
    "encoding/json"
    "net/http"
)

func writeError(w http.ResponseWriter, status int, code, detail string) {
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(status)
    _ = json.NewEncoder(w).Encode(map[string]interface{}{
        "type":   "https://docs.vto.example/errors/" + code,
        "title":  http.StatusText(status),
        "status": status,
        "detail": detail,
        "errors": []map[string]string{
            {"code": code},
        },
    })
}

func writeValidationError(w http.ResponseWriter, field, message string) {
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(http.StatusUnprocessableEntity)
    _ = json.NewEncoder(w).Encode(map[string]interface{}{
        "type":   "https://docs.vto.example/errors/validation_error",
        "title":  "Validation failed",
        "status": http.StatusUnprocessableEntity,
        "detail": "The request body failed validation",
        "errors": []map[string]string{
            {
                "code":   "validation_error",
                "field":  field,
                "detail": message,
            },
        },
    })
}
