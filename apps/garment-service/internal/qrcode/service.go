package qrcode

import (
    "bytes"
    "context"
    "crypto/hmac"
    "crypto/sha256"
    "encoding/base64"
    "encoding/json"
    "fmt"
    "time"

    "github.com/google/uuid"
    "github.com/yeqown/go-qrcode"

    vtos3 "github.com/vto/garment-service/internal/s3"
)

type QRCodeService struct {
    s3          *vtos3.Client
    tokenSecret string
    tokenTTL    time.Duration
}

func NewQRCodeService(s3 *vtos3.Client, tokenSecret string, tokenTTLHours int) *QRCodeService {
    return &QRCodeService{
        s3:          s3,
        tokenSecret: tokenSecret,
        tokenTTL:    time.Duration(tokenTTLHours) * time.Hour,
    }
}

type QRCodePayload struct {
    QRCodeID   string `json:"qr_id"`
    RetailerID string `json:"r"`
    SKU        string `json:"s"`
    IssuedAt   int64  `json:"iat"`
    ExpiresAt  int64  `json:"exp"`
    Signature  string `json:"sig"`
}

type QRCodeResult struct {
    ID           string    `json:"qr_id"`
    Payload      string    `json:"payload"`
    S3Key        string    `json:"s3_key"`
    PresignedURL string    `json:"presigned_url"`
    ExpiresAt    time.Time `json:"expires_at"`
}

func (s *QRCodeService) Generate(ctx context.Context, retailerID, sku string) (*QRCodeResult, error) {
    qrID := "qr_" + uuid.New().String()
    now := time.Now()
    expiresAt := now.Add(s.tokenTTL)

    payload := QRCodePayload{
        QRCodeID:   qrID,
        RetailerID: retailerID,
        SKU:        sku,
        IssuedAt:   now.Unix(),
        ExpiresAt:  expiresAt.Unix(),
    }
    sig := s.sign(payload)
    payload.Signature = sig

    payloadJSON, _ := json.Marshal(payload)
    payloadStr := base64.RawURLEncoding.EncodeToString(payloadJSON)
    deepLink := fmt.Sprintf("vto://qr?p=%s", payloadStr)

    pngData, err := s.generatePNG(deepLink)
    if err != nil {
        return nil, fmt.Errorf("generate png: %w", err)
    }

    s3Key := fmt.Sprintf("%s/qr/%s.png", retailerID, qrID)
    if err := s.s3.PutObject(ctx, s3Key, pngData, "image/png"); err != nil {
        return nil, fmt.Errorf("store qr png: %w", err)
    }

    presignedURL, err := s.s3.PresignedGetURL(ctx, s3Key, 24*time.Hour)
    if err != nil {
        return nil, fmt.Errorf("presign: %w", err)
    }

    return &QRCodeResult{
        ID:           qrID,
        Payload:      deepLink,
        S3Key:        s3Key,
        PresignedURL: presignedURL,
        ExpiresAt:    expiresAt,
    }, nil
}

func (s *QRCodeService) Verify(payloadStr string) (*QRCodePayload, error) {
    payloadJSON, err := base64.RawURLEncoding.DecodeString(payloadStr)
    if err != nil {
        return nil, fmt.Errorf("decode base64: %w", err)
    }
    var payload QRCodePayload
    if err := json.Unmarshal(payloadJSON, &payload); err != nil {
        return nil, fmt.Errorf("decode json: %w", err)
    }
    if time.Now().Unix() > payload.ExpiresAt {
        return nil, fmt.Errorf("qr code expired")
    }
    expectedSig := s.sign(payload)
    if !hmac.Equal([]byte(payload.Signature), []byte(expectedSig)) {
        return nil, fmt.Errorf("invalid signature")
    }
    return &payload, nil
}

func (s *QRCodeService) sign(payload QRCodePayload) string {
    h := hmac.New(sha256.New, []byte(s.tokenSecret))
    data := fmt.Sprintf("%s:%s:%s:%d:%d",
        payload.QRCodeID, payload.RetailerID, payload.SKU,
        payload.IssuedAt, payload.ExpiresAt)
    h.Write([]byte(data))
    return base64.RawURLEncoding.EncodeToString(h.Sum(nil))
}

func (s *QRCodeService) generatePNG(content string) ([]byte, error) {
    qrc, err := qrcode.New(content)
    if err != nil {
        return nil, fmt.Errorf("create qr: %w", err)
    }
    var buf bytes.Buffer
    if err := qrc.SaveTo(&buf); err != nil {
        return nil, fmt.Errorf("encode png: %w", err)
    }
    return buf.Bytes(), nil
}
