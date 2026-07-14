package garment

import (
    "context"
    "encoding/json"
    "errors"
    "fmt"
    "time"

    "github.com/google/uuid"
    "github.com/jackc/pgx/v5"
    "github.com/jackc/pgx/v5/pgxpool"

    vtos3 "github.com/vto/garment-service/internal/s3"
)

var (
    ErrNotFound      = errors.New("sku not found")
    ErrAlreadyExists = errors.New("sku already exists")
    ErrNotDigitized  = errors.New("garment not digitized")
)

type DigitizationStatus string

const (
    StatusPending    DigitizationStatus = "pending"
    StatusProcessing DigitizationStatus = "processing"
    StatusReady      DigitizationStatus = "ready"
    StatusFailed     DigitizationStatus = "failed"
    StatusManualQC   DigitizationStatus = "manual_qc"
)

type SKU struct {
    ID         uuid.UUID
    RetailerID uuid.UUID
    SKU        string
    Name       string
    Category   string
    Gender     string
    Color      string
    Fabric     string
    Metadata   map[string]interface{}
    CreatedAt  time.Time
    UpdatedAt  time.Time
}

type GarmentRepresentation struct {
    ID                  uuid.UUID
    SKUID               uuid.UUID
    RetailerID          uuid.UUID
    FrontImageURL       string
    BackImageURL        string
    SegmentationMaskURL string
    Attributes          map[string]interface{}
    QualityScore        *float64
    DigitizationStatus  DigitizationStatus
    DigitizationVersion string
    DigitizedAt         *time.Time
    FailureReason       string
}

type CreateSKURequest struct {
    RetailerID uuid.UUID
    SKU        string
    Name       string
    Category   string
    Gender     string
    Color      string
    Fabric     string
    ImageURLs  []string
    SizeChart  map[string]interface{}
    Metadata   map[string]interface{}
}

type Service struct {
    pool *pgxpool.Pool
    s3   *vtos3.Client
}

func New(pool *pgxpool.Pool, s3 *vtos3.Client) *Service {
    return &Service{pool: pool, s3: s3}
}

func (s *Service) CreateSKU(ctx context.Context, req CreateSKURequest) (*SKU, *GarmentRepresentation, error) {
    skuID := uuid.New()
    repID := uuid.New()
    now := time.Now()

    metadataJSON, _ := json.Marshal(req.Metadata)
    if req.Metadata == nil {
        metadataJSON = []byte("{}")
    }

    tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
    if err != nil {
        return nil, nil, fmt.Errorf("begin tx: %w", err)
    }
    defer tx.Rollback(ctx)

    _, err = tx.Exec(ctx, "SELECT set_config('app.retailer_id', $1, true)", req.RetailerID.String())
    if err != nil {
        return nil, nil, fmt.Errorf("set tenant context: %w", err)
    }

    _, err = tx.Exec(ctx, `
        INSERT INTO catalog.skus (id, retailer_id, sku, name, category, gender, color, fabric, metadata)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
    `, skuID, req.RetailerID, req.SKU, req.Name, req.Category, req.Gender, req.Color, req.Fabric, metadataJSON)
    if err != nil {
        return nil, nil, fmt.Errorf("insert sku: %w", err)
    }

    _, err = tx.Exec(ctx, `
        INSERT INTO catalog.garment_representations (id, sku_id, retailer_id, digitization_status)
        VALUES ($1, $2, $3, $4)
    `, repID, skuID, req.RetailerID, string(StatusPending))
    if err != nil {
        return nil, nil, fmt.Errorf("insert garment rep: %w", err)
    }

    if err := tx.Commit(ctx); err != nil {
        return nil, nil, fmt.Errorf("commit: %w", err)
    }

    sku := &SKU{
        ID: skuID, RetailerID: req.RetailerID, SKU: req.SKU, Name: req.Name,
        Category: req.Category, Gender: req.Gender, Color: req.Color, Fabric: req.Fabric,
        Metadata: req.Metadata, CreatedAt: now, UpdatedAt: now,
    }
    rep := &GarmentRepresentation{
        ID: repID, SKUID: skuID, RetailerID: req.RetailerID,
        DigitizationStatus: StatusPending,
    }
    return sku, rep, nil
}

func (s *Service) GetSKU(ctx context.Context, retailerID uuid.UUID, sku string) (*SKU, *GarmentRepresentation, error) {
    tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
    if err != nil {
        return nil, nil, fmt.Errorf("begin tx: %w", err)
    }
    defer tx.Rollback(ctx)

    _, err = tx.Exec(ctx, "SELECT set_config('app.retailer_id', $1, true)", retailerID.String())
    if err != nil {
        return nil, nil, fmt.Errorf("set tenant context: %w", err)
    }

    var (
        skuID     uuid.UUID
        retID     uuid.UUID
        name      *string
        category  *string
        gender    *string
        color     *string
        fabric    *string
        metadata  []byte
        createdAt time.Time
        updatedAt time.Time
    )

    err = tx.QueryRow(ctx, `
        SELECT id, retailer_id, sku, name, category, gender, color, fabric, metadata, created_at, updated_at
        FROM catalog.skus
        WHERE retailer_id = $1 AND sku = $2 AND deleted_at IS NULL
    `, retailerID, sku).Scan(&skuID, &retID, &sku, &name, &category, &gender, &color, &fabric, &metadata, &createdAt, &updatedAt)

    if err != nil {
        if errors.Is(err, pgx.ErrNoRows) {
            return nil, nil, ErrNotFound
        }
        return nil, nil, fmt.Errorf("query sku: %w", err)
    }

    skuObj := &SKU{
        ID: skuID, RetailerID: retID, SKU: sku,
        CreatedAt: createdAt, UpdatedAt: updatedAt,
    }
    if name != nil { skuObj.Name = *name }
    if category != nil { skuObj.Category = *category }
    if gender != nil { skuObj.Gender = *gender }
    if color != nil { skuObj.Color = *color }
    if fabric != nil { skuObj.Fabric = *fabric }
    if metadata != nil { _ = json.Unmarshal(metadata, &skuObj.Metadata) }

    return skuObj, nil, nil
}

func (s *Service) ListSKUs(ctx context.Context, retailerID uuid.UUID, limit int, offset int) ([]SKU, error) {
    tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
    if err != nil {
        return nil, fmt.Errorf("begin tx: %w", err)
    }
    defer tx.Rollback(ctx)

    _, err = tx.Exec(ctx, "SELECT set_config('app.retailer_id', $1, true)", retailerID.String())
    if err != nil {
        return nil, fmt.Errorf("set tenant context: %w", err)
    }

    if limit <= 0 || limit > 200 { limit = 50 }

    rows, err := tx.Query(ctx, `
        SELECT id, retailer_id, sku, COALESCE(name, ''), COALESCE(category, ''),
               COALESCE(gender, ''), COALESCE(color, ''), COALESCE(fabric, ''), created_at, updated_at
        FROM catalog.skus
        WHERE deleted_at IS NULL
        ORDER BY created_at DESC
        LIMIT $1 OFFSET $2
    `, limit, offset)
    if err != nil {
        return nil, fmt.Errorf("query skus: %w", err)
    }
    defer rows.Close()

    var skus []SKU
    for rows.Next() {
        var s SKU
        if err := rows.Scan(&s.ID, &s.RetailerID, &s.SKU, &s.Name, &s.Category,
            &s.Gender, &s.Color, &s.Fabric, &s.CreatedAt, &s.UpdatedAt); err != nil {
            return nil, fmt.Errorf("scan sku: %w", err)
        }
        skus = append(skus, s)
    }
    return skus, nil
}

func (s *Service) DeleteSKU(ctx context.Context, retailerID uuid.UUID, sku string) error {
    tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
    if err != nil {
        return fmt.Errorf("begin tx: %w", err)
    }
    defer tx.Rollback(ctx)

    _, err = tx.Exec(ctx, "SELECT set_config('app.retailer_id', $1, true)", retailerID.String())
    if err != nil {
        return fmt.Errorf("set tenant context: %w", err)
    }

    tag, err := tx.Exec(ctx, `
        UPDATE catalog.skus SET deleted_at = NOW()
        WHERE retailer_id = $1 AND sku = $2 AND deleted_at IS NULL
    `, retailerID, sku)
    if err != nil {
        return fmt.Errorf("delete sku: %w", err)
    }
    if tag.RowsAffected() == 0 {
        return ErrNotFound
    }
    return tx.Commit(ctx)
}
