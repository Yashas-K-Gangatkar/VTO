package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/rs/zerolog"
)

func TestRequestID_GeneratesWhenAbsent(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/v1/health", nil)
	rec := httptest.NewRecorder()

	called := false
	next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		called = true
		if r.Header.Get("X-Request-Id") == "" {
			// request header won't be set; we set it on the response
		}
	})

	RequestID(next).ServeHTTP(rec, req)

	if !called {
		t.Fatal("next handler not called")
	}
	if rec.Header().Get("X-Request-Id") == "" {
		t.Error("expected X-Request-Id response header to be set")
	}
}

func TestRequestID_PreservesWhenPresent(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/v1/health", nil)
	req.Header.Set("X-Request-Id", "test-req-id-123")
	rec := httptest.NewRecorder()

	RequestID(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {})).ServeHTTP(rec, req)

	if got := rec.Header().Get("X-Request-Id"); got != "test-req-id-123" {
		t.Errorf("expected preserved X-Request-Id, got %q", got)
	}
}

func TestRecoverer_RecoversFromPanic(t *testing.T) {
	logger := zerolog.Nop()
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	rec := httptest.NewRecorder()

	next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		panic("boom")
	})

	Recoverer(logger)(next).ServeHTTP(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Errorf("expected 500, got %d", rec.Code)
	}
}

func TestGenerateID_ReturnsNonEmpty(t *testing.T) {
	id := generateID()
	if id == "" {
		t.Error("expected non-empty ID")
	}
	// Ensure uniqueness across rapid calls
	time.Sleep(1 * time.Nanosecond)
	id2 := generateID()
	if id == id2 {
		t.Error("expected unique IDs")
	}
}
