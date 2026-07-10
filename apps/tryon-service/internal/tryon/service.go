package tryon

import (
    "context"
    "crypto/sha256"
    "encoding/hex"
    "errors"
    "fmt"
    "time"

    "github.com/google/uuid"
    "github.com/jackc/pgx/v5"
    "github.com/jackc/pgx/v5/pgxpool"

    "github.com/tryon-service/internal/cache"
)

var ErrNotFound = errors.New("tryon not found")
var ErrGarmentNotDigitized = errors.New("garment not digitized")
var ErrBodyProfileExpired = errors.New("body profile expired")

type Status string

const (
    StatusPending   Status = "pending"
    StatusProcessing Status = "processing"
    StatusSucceeded Status = "succeeded"
    StatusFailed    Status = "failed"
    StatusExpired   Status = "expired"
)

type TryOn struct {
    ID              uuid.UUID
    RetailerID      uuid.UUID
    ShopperRef      string
    BodyProfileID   uuid.UUID
    SkuID           uuid.UUID
    GarmentSKU      string
    Size            string
    View            string
    Status          Status
    ImageURL        string
    ImageExpiresAt  *time.Time
    ThumbnailURL    string
    QualityScore    *float64
    ModelVersion    string
    RenderTimeMs    *int
    ErrorCode       string
    ErrorDetail     string
    CacheKey        string
    Billed          bool
    BilledAt        *time.Time
    CreatedAt       time.Time
    CompletedAt     *time.Time
}

type CreateRequest struct {
    RetailerID    uuid.UUID
    ShopperRef    string
    BodyProfileID uuid.UUID
    GarmentSKU    string
    Size          string
    View          string
}

type Service struct {
    pool         *pgxpool.Pool
    cache        *cache.Redis
    cacheTTL     time.Duration
}

func New(pool *pgxpool.Pool, cache *cache.Redis, cacheTTLHours int) *Service {
    return &Service{
        pool:     pool,
        cache:    cache,
        cacheTTL: time.Duration(cacheTTLHours) * time.Hour,
    }
}

func (s *Service) computeCacheKey(retailerID, bodyProfileID, garmentSKU, size, view string) string {
    raw := fmt.Sprintf("%s:%s:%s:%s:%s", retailerID, bodyProfileID, garmentSKU, size, view)
    h := sha256.Sum256([]byte(raw))
    return hex.EncodeToString(h[:])
}

func (s *Service) Create(ctx context.Context, req CreateRequest) (*TryOn, error) {
    if req.View == "" {
        req.View = "front"
    }

    cacheKey := s.computeCacheKey(
        req.RetailerID.String(),
        req.BodyProfileID.String(),
        req.GarmentSKU,
        req.Size,
        req.View,
    )

    cached, err := s.cache.GetTryOn(ctx, cacheKey)
    if err != nil {
        return nil, fmt.Errorf("check cache: %w", err)
    }

    if cached != nil {
        return s.createCachedRecord(ctx, req, cacheKey, cached)
    }

    tryonID := uuid.New()
    now := time.Now()

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
        INSERT INTO tryon.tryons (
            id, retailer_id, shopper_ref, body_profile_id, sku_id, garment_sku,
            size, view, status, cache_key
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
    `, tryonID, req.RetailerID, req.ShopperRef, req.BodyProfileID, uuid.Nil, req.GarmentSKU,
        req.Size, req.View, string(StatusPending), cacheKey)
    if err != nil {
        return nil, fmt.Errorf("insert tryon: %w", err)
    }

    if err := tx.Commit(ctx); err != nil {
        return nil, fmt.Errorf("commit: %w", err)
    }

    return &TryOn{
        ID:            tryonID,
        RetailerID:    req.RetailerID,
        ShopperRef:    req.ShopperRef,
        BodyProfileID: req.BodyProfileID,
        GarmentSKU:    req.GarmentSKU,
        Size:          req.Size,
        View:          req.View,
        Status:        StatusPending,
        CacheKey:      cacheKey,
        CreatedAt:     now,
    }, nil
}

func (s *Service) createCachedRecord(ctx context.Context, req CreateRequest, cacheKey string, cached *cache.CachedTryOn) (*TryOn, error) {
    tryonID := uuid.New()
    now := time.Now()

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
        INSERT INTO tryon.tryons (
            id, retailer_id, shopper_ref, body_profile_id, sku_id, garment_sku,
            size, view, status, image_url, thumbnail_url, quality_score, model_version,
            render_time_ms, cache_key, completed_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
    `, tryonID, req.RetailerID, req.ShopperRef, req.BodyProfileID, uuid.Nil, req.GarmentSKU,
        req.Size, req.View, string(StatusSucceeded), cached.ImageURL, cached.ThumbnailURL,
        cached.QualityScore, cached.ModelVersion, cached.RenderTimeMs, cacheKey, now)
    if err != nil {
        return nil, fmt.Errorf("insert cached tryon: %w", err)
    }

    if err := tx.Commit(ctx); err != nil {
        return nil, fmt.Errorf("commit: %w", err)
    }

    return &TryOn{
        ID:            tryonID,
        RetailerID:    req.RetailerID,
        ShopperRef:    req.ShopperRef,
        BodyProfileID: req.BodyProfileID,
        GarmentSKU:    req.GarmentSKU,
        Size:          req.Size,
        View:          req.View,
        Status:        StatusSucceeded,
        ImageURL:      cached.ImageURL,
        ThumbnailURL:  cached.ThumbnailURL,
        QualityScore:  &cached.QualityScore,
        ModelVersion:  cached.ModelVersion,
        RenderTimeMs:  &cached.RenderTimeMs,
        CacheKey:      cacheKey,
        CreatedAt:     now,
        CompletedAt:   &now,
    }, nil
}

func (s *Service) Get(ctx context.Context, retailerID, tryonID uuid.UUID) (*TryOn, error) {
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
        id            uuid.UUID
        retID         uuid.UUID
        shopperRef    string
        bodyProfileID uuid.UUID
        skuID         uuid.UUID
        garmentSKU    string
        size          *string
        view          string
        status        string
        imageURL      *string
        imageExpires  *time.Time
        thumbnailURL  *string
        qualityScore  *float64
        modelVersion  *string
        renderTimeMs  *int
        errorCode     *string
        errorDetail   *string
        cacheKey      *string
        billed        bool
        billedAt      *time.Time
        createdAt     time.Time
        completedAt   *time.Time
    )

    err = tx.QueryRow(ctx, `
        SELECT id, retailer_id, shopper_ref, body_profile_id, sku_id, garment_sku,
            size, view, status::text, image_url, image_expires_at, thumbnail_url,
            quality_score, model_version, render_time_ms, error_code, error_detail,
            cache_key, billed, billed_at, created_at, completed_at
        FROM tryon.tryons
        WHERE id = $1 AND deleted_at IS NULL
    `, tryonID).Scan(&id, &retID, &shopperRef, &bodyProfileID, &skuID, &garmentSKU,
        &size, &view, &status, &imageURL, &imageExpires, &thumbnailURL,
        &qualityScore, &modelVersion, &renderTimeMs, &errorCode, &errorDetail,
        &cacheKey, &billed, &billedAt, &createdAt, &completedAt)

    if err != nil {
        if errors.Is(err, pgx.ErrNoRows) {
            return nil, ErrNotFound
        }
        return nil, fmt.Errorf("query tryon: %w", err)
    }

    t := &TryOn{
        ID:            id,
        RetailerID:    retID,
        ShopperRef:    shopperRef,
        BodyProfileID: bodyProfileID,
        SkuID:         skuID,
        GarmentSKU:    garmentSKU,
        View:          view,
        Status:        Status(status),
        Billed:        billed,
        CreatedAt:     createdAt,
    }
    if size != nil {
        t.Size = *size
    }
    if imageURL != nil {
        t.ImageURL = *imageURL
    }
    t.ImageExpiresAt = imageExpires
    if thumbnailURL != nil {
        t.ThumbnailURL = *thumbnailURL
    }
    t.QualityScore = qualityScore
    if modelVersion != nil {
        t.ModelVersion = *modelVersion
    }
    t.RenderTimeMs = renderTimeMs
    if errorCode != nil {
        t.ErrorCode = *errorCode
    }
    if errorDetail != nil {
        t.ErrorDetail = *errorDetail
    }
    if cacheKey != nil {
        t.CacheKey = *cacheKey
    }
    t.BilledAt = billedAt
    t.CompletedAt = completedAt

    return t, nil
}

func (s *Service) MarkSucceeded(ctx context.Context, retailerID, tryonID uuid.UUID, imageURL, thumbnailURL, modelVersion string, qualityScore float64, renderTimeMs int) error {
    tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
    if err != nil {
        return fmt.Errorf("begin tx: %w", err)
    }
    defer tx.Rollback(ctx)

    _, err = tx.Exec(ctx, "SET LOCAL app.retailer_id = $1", retailerID.String())
    if err != nil {
        return fmt.Errorf("set tenant context: %w", err)
    }

    var cacheKey *string
    err = tx.QueryRow(ctx, `
        UPDATE tryon.tryons
        SET status = 'succeeded', image_url = $1, thumbnail_url = $2,
            quality_score = $3, model_version = $4, render_time_ms = $5,
            completed_at = NOW()
        WHERE id = $6 AND status IN ('pending', 'processing')
        RETURNING cache_key
    `, imageURL, thumbnailURL, qualityScore, modelVersion, renderTimeMs, tryonID).Scan(&cacheKey)

    if err != nil {
        if errors.Is(err, pgx.ErrNoRows) {
            return ErrNotFound
        }
        return fmt.Errorf("update tryon: %w", err)
    }

    if err := tx.Commit(ctx); err != nil {
        return fmt.Errorf("commit: %w", err)
    }

    if cacheKey != nil && *cacheKey != "" {
        cached := &cache.CachedTryOn{
            TryOnID:      tryonID.String(),
            ImageURL:     imageURL,
            ThumbnailURL: thumbnailURL,
            QualityScore: qualityScore,
            ModelVersion: modelVersion,
            RenderTimeMs: renderTimeMs,
        }
        if err := s.cache.SetTryOn(ctx, *cacheKey, cached, s.cacheTTL); err != nil {
            fmt.Printf("WARN: failed to cache tryon result: %v\n", err)
        }
    }

    return nil
}

func (s *Service) MarkFailed(ctx context.Context, retailerID, tryonID uuid.UUID, errorCode, errorDetail string) error {
    tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
    if err != nil {
        return fmt.Errorf("begin tx: %w", err)
    }
    defer tx.Rollback(ctx)

    _, err = tx.Exec(ctx, "SET LOCAL app.retailer_id = $1", retailerID.String())
    if err != nil {
        return fmt.Errorf("set tenant context: %w", err)
    }

    tag, err := tx.Exec(ctx, `
        UPDATE tryon.tryons
        SET status = 'failed', error_code = $1, error_detail = $2, completed_at = NOW()
        WHERE id = $3 AND status IN ('pending', 'processing')
    `, errorCode, errorDetail, tryonID)
    if err != nil {
        return fmt.Errorf("update tryon: %w", err)
    }

    if tag.RowsAffected() == 0 {
        return ErrNotFound
    }

    return tx.Commit(ctx)
}

func (s *Service) MarkViewed(ctx context.Context, retailerID, tryonID uuid.UUID) (bool, error) {
    alreadyViewed, err := s.cache.IsViewed(ctx, tryonID.String())
    if err != nil {
        return false, fmt.Errorf("check dedup: %w", err)
    }
    if alreadyViewed {
        return false, nil
    }

    if err := s.cache.MarkViewed(ctx, tryonID.String(), s.cacheTTL); err != nil {
        return false, fmt.Errorf("mark viewed: %w", err)
    }

    tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
    if err != nil {
        return false, fmt.Errorf("begin tx: %w", err)
    }
    defer tx.Rollback(ctx)

    _, err = tx.Exec(ctx, "SET LOCAL app.retailer_id = $1", retailerID.String())
    if err != nil {
        return false, fmt.Errorf("set tenant context: %w", err)
    }

    _, err = tx.Exec(ctx, `
        UPDATE tryon.tryons
        SET billed = TRUE, billed_at = NOW()
        WHERE id = $1 AND billed = FALSE
    `, tryonID)
    if err != nil {
        return false, fmt.Errorf("mark billed: %w", err)
    }

    if err := tx.Commit(ctx); err != nil {
        return false, fmt.Errorf("commit: %w", err)
    }

    return true, nil
}
