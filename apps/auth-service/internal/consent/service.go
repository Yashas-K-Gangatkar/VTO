package consent

import (
    "context"
    "errors"
    "fmt"
    "time"

    "github.com/google/uuid"
    "github.com/jackc/pgx/v5"
    "github.com/jackc/pgx/v5/pgxpool"
)

type ConsentType string

const (
    ConsentTypeBodyScan    ConsentType = "body_scan"
    ConsentTypeTrainingUse ConsentType = "training_use"
)

type Record struct {
    ID             uuid.UUID
    RetailerID     uuid.UUID
    ShopperRef     string
    ConsentType    ConsentType
    ConsentVersion string
    ConsentedAt    time.Time
    RevokedAt      *time.Time
    IPAddress      string
    UserAgent      string
    Signature      string
}

var ErrNotFound = errors.New("consent record not found")
var ErrNoActiveConsent = errors.New("no active consent")

type Service struct {
    pool *pgxpool.Pool
}

func New(pool *pgxpool.Pool) *Service {
    return &Service{pool: pool}
}

func (s *Service) Record(ctx context.Context, retailerID uuid.UUID, shopperRef string, consentType ConsentType, version, signature, ipAddress, userAgent string) (*Record, error) {
    id := uuid.New()

    tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
    if err != nil {
        return nil, fmt.Errorf("begin tx: %w", err)
    }
    defer tx.Rollback(ctx)

    _, err = tx.Exec(ctx, "SET LOCAL app.retailer_id = $1", retailerID.String())
    if err != nil {
        return nil, fmt.Errorf("set tenant context: %w", err)
    }

    _, err = tx.Exec(ctx, `
        INSERT INTO auth.consent_records (id, retailer_id, shopper_ref, consent_type, consent_version, ip_address, user_agent, signature)
        VALUES ($1, $2, $3, $4, $5, $6::inet, $7, $8)
    `, id, retailerID, shopperRef, string(consentType), version, ipAddress, userAgent, signature)
    if err != nil {
        return nil, fmt.Errorf("insert consent: %w", err)
    }

    if err := tx.Commit(ctx); err != nil {
        return nil, fmt.Errorf("commit: %w", err)
    }

    return &Record{
        ID:             id,
        RetailerID:     retailerID,
        ShopperRef:     shopperRef,
        ConsentType:    consentType,
        ConsentVersion: version,
        ConsentedAt:    time.Now(),
        IPAddress:      ipAddress,
        UserAgent:      userAgent,
        Signature:      signature,
    }, nil
}

func (s *Service) HasActiveConsent(ctx context.Context, retailerID uuid.UUID, shopperRef string, consentType ConsentType) (bool, error) {
    tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
    if err != nil {
        return false, fmt.Errorf("begin tx: %w", err)
    }
    defer tx.Rollback(ctx)

    _, err = tx.Exec(ctx, "SET LOCAL app.retailer_id = $1", retailerID.String())
    if err != nil {
        return false, fmt.Errorf("set tenant context: %w", err)
    }

    var exists bool
    err = tx.QueryRow(ctx, `
        SELECT EXISTS(
            SELECT 1 FROM auth.consent_records
            WHERE retailer_id = $1 AND shopper_ref = $2 AND consent_type = $3 AND revoked_at IS NULL
        )
    `, retailerID, shopperRef, string(consentType)).Scan(&exists)
    if err != nil {
        return false, fmt.Errorf("query consent: %w", err)
    }

    return exists, nil
}

func (s *Service) ListForShopper(ctx context.Context, retailerID uuid.UUID, shopperRef string) ([]Record, error) {
    tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
    if err != nil {
        return nil, fmt.Errorf("begin tx: %w", err)
    }
    defer tx.Rollback(ctx)

    _, err = tx.Exec(ctx, "SET LOCAL app.retailer_id = $1", retailerID.String())
    if err != nil {
        return nil, fmt.Errorf("set tenant context: %w", err)
    }

    rows, err := tx.Query(ctx, `
        SELECT id, retailer_id, shopper_ref, consent_type, consent_version, consented_at, revoked_at, ip_address::text, user_agent, signature
        FROM auth.consent_records
        WHERE shopper_ref = $1
        ORDER BY consented_at DESC
    `, shopperRef)
    if err != nil {
        return nil, fmt.Errorf("query consent records: %w", err)
    }
    defer rows.Close()

    var records []Record
    for rows.Next() {
        var r Record
        if err := rows.Scan(&r.ID, &r.RetailerID, &r.ShopperRef, &r.ConsentType, &r.ConsentVersion, &r.ConsentedAt, &r.RevokedAt, &r.IPAddress, &r.UserAgent, &r.Signature); err != nil {
            return nil, fmt.Errorf("scan consent record: %w", err)
        }
        records = append(records, r)
    }

    return records, nil
}

func (s *Service) Revoke(ctx context.Context, retailerID uuid.UUID, shopperRef string, consentType ConsentType) error {
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
        UPDATE auth.consent_records
        SET revoked_at = NOW()
        WHERE retailer_id = $1 AND shopper_ref = $2 AND consent_type = $3 AND revoked_at IS NULL
    `, retailerID, shopperRef, string(consentType))
    if err != nil {
        return fmt.Errorf("revoke consent: %w", err)
    }

    if tag.RowsAffected() == 0 {
        return ErrNoActiveConsent
    }

    return tx.Commit(ctx)
}
