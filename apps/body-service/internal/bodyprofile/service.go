package bodyprofile

import (
    "context"
    "encoding/json"
    "errors"
    "fmt"
    "time"

    "github.com/google/uuid"
    "github.com/jackc/pgx/v5"
    "github.com/jackc/pgx/v5/pgxpool"

    "github.com/vto/body-service/internal/encryption"
    vtos3 "github.com/vto/body-service/internal/s3"
)

var ErrNotFound = errors.New("body profile not found")
var ErrExpired = errors.New("body profile expired")

type BodyProfile struct {
    ID           uuid.UUID
    RetailerID   uuid.UUID
    ShopperRef   string
    Measurements map[string]float64
    ScanDevice   string
    QualityScore float64
    Status       string
    CreatedAt    time.Time
    ExpiresAt    time.Time
}

type CreateRequest struct {
    RetailerID   uuid.UUID
    ShopperRef   string
    ScanData     []byte
    ScanDevice   string
    QualityScore float64
    Measurements map[string]float64
    TTLDays      int
}

type Service struct {
    pool           *pgxpool.Pool
    s3             *vtos3.Client
    encryption     *encryption.Client
    defaultTTLDays int
}

func New(pool *pgxpool.Pool, s3 *vtos3.Client, enc *encryption.Client, defaultTTLDays int) *Service {
    return &Service{pool: pool, s3: s3, encryption: enc, defaultTTLDays: defaultTTLDays}
}

func (s *Service) Create(ctx context.Context, req CreateRequest) (*BodyProfile, error) {
    if req.TTLDays <= 0 {
        req.TTLDays = s.defaultTTLDays
    }

    profileID := uuid.New()
    now := time.Now()
    expiresAt := now.AddDate(0, 0, req.TTLDays)

    encryptedData, err := s.encryption.Encrypt(req.ScanData)
    if err != nil {
        return nil, fmt.Errorf("encrypt scan data: %w", err)
    }

    blobKey := s.s3.GenerateKey(req.RetailerID.String(), profileID.String())
    if err := s.s3.PutObject(ctx, blobKey, encryptedData, "application/octet-stream"); err != nil {
        return nil, fmt.Errorf("store encrypted blob: %w", err)
    }

    previewPNG, err := GeneratePreviewPNG(req.Measurements)
    if err != nil {
        return nil, fmt.Errorf("generate preview: %w", err)
    }
    previewKey := fmt.Sprintf("%s/%s.png", req.RetailerID, profileID)
    if err := s.s3.PutObject(ctx, previewKey, previewPNG, "image/png"); err != nil {
        return nil, fmt.Errorf("store preview png: %w", err)
    }

    measurementsJSON, _ := json.Marshal(req.Measurements)

    tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
    if err != nil {
        return nil, fmt.Errorf("begin tx: %w", err)
    }
    defer tx.Rollback(ctx)

    _, err = tx.Exec(ctx, "SET LOCAL app.retailer_id = $1", req.RetailerID.String())
    if err != nil {
        return nil, fmt.Errorf("set tenant context: %w", err)
    }

    _, err = tx.Exec(ctx, `
        INSERT INTO body.body_profiles (
            id, retailer_id, shopper_ref, smplx_blob_key, smplx_blob_kms_key_id,
            measurements, scan_device, scan_quality_score, expires_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
    `, profileID, req.RetailerID, req.ShopperRef, blobKey, "local-dev-key",
        measurementsJSON, req.ScanDevice, req.QualityScore, expiresAt)
    if err != nil {
        _ = s.s3.DeleteObject(ctx, blobKey)
        _ = s.s3.DeleteObject(ctx, previewKey)
        return nil, fmt.Errorf("insert body profile: %w", err)
    }

    if err := tx.Commit(ctx); err != nil {
        _ = s.s3.DeleteObject(ctx, blobKey)
        _ = s.s3.DeleteObject(ctx, previewKey)
        return nil, fmt.Errorf("commit: %w", err)
    }

    return &BodyProfile{
        ID:           profileID,
        RetailerID:   req.RetailerID,
        ShopperRef:   req.ShopperRef,
        Measurements: req.Measurements,
        ScanDevice:   req.ScanDevice,
        QualityScore: req.QualityScore,
        Status:       "ready",
        CreatedAt:    now,
        ExpiresAt:    expiresAt,
    }, nil
}

func (s *Service) Get(ctx context.Context, retailerID, profileID uuid.UUID) (*BodyProfile, error) {
    tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
    if err != nil {
        return nil, fmt.Errorf("begin tx: %w", err)
    }
    defer tx.Rollback(ctx)

    _, err = tx.Exec(ctx, "SET LOCAL app.retailer_id = $1", retailerID.String())
    if err != nil {
        return nil, fmt.Errorf("set tenant context: %w", err)
    }

    var (
        id           uuid.UUID
        retID        uuid.UUID
        shopperRef   string
        measurements []byte
        scanDevice   *string
        qualityScore *float64
        createdAt    time.Time
        expiresAt    time.Time
    )

    err = tx.QueryRow(ctx, `
        SELECT id, retailer_id, shopper_ref, measurements, scan_device, scan_quality_score, created_at, expires_at
        FROM body.body_profiles
        WHERE id = $1 AND deleted_at IS NULL
    `, profileID).Scan(&id, &retID, &shopperRef, &measurements, &scanDevice, &qualityScore, &createdAt, &expiresAt)

    if err != nil {
        if errors.Is(err, pgx.ErrNoRows) {
            return nil, ErrNotFound
        }
        return nil, fmt.Errorf("query body profile: %w", err)
    }

    if time.Now().After(expiresAt) {
        return nil, ErrExpired
    }

    var meas map[string]float64
    if err := json.Unmarshal(measurements, &meas); err != nil {
        return nil, fmt.Errorf("unmarshal measurements: %w", err)
    }

    profile := &BodyProfile{
        ID:           id,
        RetailerID:   retID,
        ShopperRef:   shopperRef,
        Measurements: meas,
        CreatedAt:    createdAt,
        ExpiresAt:    expiresAt,
        Status:       "ready",
    }
    if scanDevice != nil {
        profile.ScanDevice = *scanDevice
    }
    if qualityScore != nil {
        profile.QualityScore = *qualityScore
    }

    return profile, nil
}

func (s *Service) Delete(ctx context.Context, retailerID, profileID uuid.UUID) error {
    tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
    if err != nil {
        return fmt.Errorf("begin tx: %w", err)
    }
    defer tx.Rollback(ctx)

    _, err = tx.Exec(ctx, "SET LOCAL app.retailer_id = $1", retailerID.String())
    if err != nil {
        return fmt.Errorf("set tenant context: %w", err)
    }

    var blobKey string
    err = tx.QueryRow(ctx, `
        UPDATE body.body_profiles
        SET deleted_at = NOW()
        WHERE id = $1 AND deleted_at IS NULL
        RETURNING smplx_blob_key
    `, profileID).Scan(&blobKey)

    if err != nil {
        if errors.Is(err, pgx.ErrNoRows) {
            return ErrNotFound
        }
        return fmt.Errorf("mark deleted: %w", err)
    }

    if err := tx.Commit(ctx); err != nil {
        return fmt.Errorf("commit: %w", err)
    }

    go func() {
        bgCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
        defer cancel()
        _ = s.s3.DeleteObject(bgCtx, blobKey)
        _ = s.s3.DeleteObject(bgCtx, fmt.Sprintf("%s/%s.png", retailerID, profileID))
    }()

    return nil
}
