package apikey

import (
    "context"
    "crypto/rand"
    "crypto/sha256"
    "encoding/hex"
    "errors"
    "fmt"
    "time"

    "github.com/google/uuid"
    "github.com/jackc/pgx/v5"
    "github.com/jackc/pgx/v5/pgxpool"
)

type APIKey struct {
    ID         uuid.UUID
    RetailerID uuid.UUID
    Name       string
    KeyPrefix  string
    Scopes     []string
    LastUsedAt *time.Time
    CreatedAt  time.Time
    CreatedBy  *uuid.UUID
    RevokedAt  *time.Time
}

type FullAPIKey struct {
    APIKey
    Key string
}

var ErrNotFound = errors.New("api key not found")
var ErrInvalidKey = errors.New("invalid api key")

type Service struct {
    pool *pgxpool.Pool
}

func New(pool *pgxpool.Pool) *Service {
    return &Service{pool: pool}
}

func generateKey() (full string, prefix string, hash string, err error) {
    randomBytes := make([]byte, 24)
    if _, err := rand.Read(randomBytes); err != nil {
        return "", "", "", fmt.Errorf("generate random bytes: %w", err)
    }
    hexStr := hex.EncodeToString(randomBytes)

    prefixBytes := make([]byte, 2)
    if _, err := rand.Read(prefixBytes); err != nil {
        return "", "", "", fmt.Errorf("generate prefix: %w", err)
    }
    prefixStr := hex.EncodeToString(prefixBytes)

    full = fmt.Sprintf("vto_%s_%s", prefixStr, hexStr)
    prefix = fmt.Sprintf("vto_%s", prefixStr)

    h := sha256.Sum256([]byte(full))
    hash = hex.EncodeToString(h[:])

    return full, prefix, hash, nil
}

func (s *Service) Create(ctx context.Context, retailerID uuid.UUID, name string, scopes []string, createdBy *uuid.UUID) (*FullAPIKey, error) {
    if scopes == nil {
        scopes = []string{"server_to_server"}
    }

    fullKey, prefix, hash, err := generateKey()
    if err != nil {
        return nil, err
    }

    id := uuid.New()
    now := time.Now()

    tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
    if err != nil {
        return nil, fmt.Errorf("begin tx: %w", err)
    }
    defer tx.Rollback(ctx)

    _, err = tx.Exec(ctx, "SELECT set_config('app.retailer_id', $1, true)", retailerID.String())
    if err != nil {
        return nil, fmt.Errorf("set tenant context: %w", err)
    }

    _, err = tx.Exec(ctx, `
        INSERT INTO auth.api_keys (id, retailer_id, name, key_hash, key_prefix, scopes, created_by)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
    `, id, retailerID, name, hash, prefix, scopes, createdBy)
    if err != nil {
        return nil, fmt.Errorf("insert api key: %w", err)
    }

    if err := tx.Commit(ctx); err != nil {
        return nil, fmt.Errorf("commit: %w", err)
    }

    return &FullAPIKey{
        APIKey: APIKey{
            ID:         id,
            RetailerID: retailerID,
            Name:       name,
            KeyPrefix:  prefix,
            Scopes:     scopes,
            CreatedAt:  now,
            CreatedBy:  createdBy,
        },
        Key: fullKey,
    }, nil
}

func (s *Service) Verify(ctx context.Context, fullKey string) (*APIKey, error) {
    h := sha256.Sum256([]byte(fullKey))
    hash := hex.EncodeToString(h[:])

    var (
        id         uuid.UUID
        retailerID uuid.UUID
        name       string
        prefix     string
        scopes     []string
        lastUsed   *time.Time
        createdAt  time.Time
    )

    err := s.pool.QueryRow(ctx, `
        SELECT id, retailer_id, name, key_prefix, scopes, last_used_at, created_at
        FROM auth.api_keys
        WHERE key_hash = $1 AND revoked_at IS NULL
    `, hash).Scan(&id, &retailerID, &name, &prefix, &scopes, &lastUsed, &createdAt)

    if err != nil {
        if errors.Is(err, pgx.ErrNoRows) {
            return nil, ErrInvalidKey
        }
        return nil, fmt.Errorf("query api key: %w", err)
    }

    go func() {
        bgCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
        defer cancel()
        _, _ = s.pool.Exec(bgCtx, `
            UPDATE auth.api_keys SET last_used_at = NOW() WHERE id = $1
        `, id)
    }()

    return &APIKey{
        ID:         id,
        RetailerID: retailerID,
        Name:       name,
        KeyPrefix:  prefix,
        Scopes:     scopes,
        LastUsedAt: lastUsed,
        CreatedAt:  createdAt,
    }, nil
}

func (s *Service) List(ctx context.Context, retailerID uuid.UUID) ([]APIKey, error) {
    tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{})
    if err != nil {
        return nil, fmt.Errorf("begin tx: %w", err)
    }
    defer tx.Rollback(ctx)

    _, err = tx.Exec(ctx, "SELECT set_config('app.retailer_id', $1, true)", retailerID.String())
    if err != nil {
        return nil, fmt.Errorf("set tenant context: %w", err)
    }

    rows, err := tx.Query(ctx, `
        SELECT id, retailer_id, name, key_prefix, scopes, last_used_at, created_at, created_by
        FROM auth.api_keys
        WHERE revoked_at IS NULL
        ORDER BY created_at DESC
    `)
    if err != nil {
        return nil, fmt.Errorf("query api keys: %w", err)
    }
    defer rows.Close()

    var keys []APIKey
    for rows.Next() {
        var k APIKey
        if err := rows.Scan(&k.ID, &k.RetailerID, &k.Name, &k.KeyPrefix, &k.Scopes, &k.LastUsedAt, &k.CreatedAt, &k.CreatedBy); err != nil {
            return nil, fmt.Errorf("scan api key: %w", err)
        }
        keys = append(keys, k)
    }

    if err := rows.Err(); err != nil {
        return nil, fmt.Errorf("iterate rows: %w", err)
    }

    return keys, nil
}

func (s *Service) Revoke(ctx context.Context, retailerID, keyID uuid.UUID, reason string) error {
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
        UPDATE auth.api_keys
        SET revoked_at = NOW(), revoked_reason = $1
        WHERE id = $2 AND retailer_id = $3 AND revoked_at IS NULL
    `, reason, keyID, retailerID)
    if err != nil {
        return fmt.Errorf("revoke api key: %w", err)
    }

    if tag.RowsAffected() == 0 {
        return ErrNotFound
    }

    return tx.Commit(ctx)
}

// CreateWithoutRLS creates an API key without setting the RLS tenant context.
// Used by the CLI bootstrap tool which runs outside a tenant context.
func (s *Service) CreateWithoutRLS(ctx context.Context, retailerID uuid.UUID, name string, scopes []string, createdBy *uuid.UUID) (*FullAPIKey, error) {
    if scopes == nil {
        scopes = []string{"server_to_server"}
    }

    fullKey, prefix, hash, err := generateKey()
    if err != nil {
        return nil, err
    }

    id := uuid.New()
    now := time.Now()

    // Insert directly without SET LOCAL (bypasses RLS — only for bootstrap)
    _, err = s.pool.Exec(ctx, `
        INSERT INTO auth.api_keys (id, retailer_id, name, key_hash, key_prefix, scopes, created_by)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
    `, id, retailerID, name, hash, prefix, scopes, createdBy)
    if err != nil {
        return nil, fmt.Errorf("insert api key: %w", err)
    }

    return &FullAPIKey{
        APIKey: APIKey{
            ID:         id,
            RetailerID: retailerID,
            Name:       name,
            KeyPrefix:  prefix,
            Scopes:     scopes,
            CreatedAt:  now,
            CreatedBy:  createdBy,
        },
        Key: fullKey,
    }, nil
}
