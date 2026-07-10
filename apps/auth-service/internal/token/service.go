package token

import (
    "context"
    "errors"
    "fmt"
    "time"

    "github.com/jackc/pgx/v5"
    "github.com/jackc/pgx/v5/pgxpool"
    "github.com/redis/go-redis/v9"

    "github.com/vto/auth-service/internal/jwt"
)

var ErrInvalidToken = errors.New("invalid token")

type Service struct {
    pool   *pgxpool.Pool
    rdb    *redis.Client
    signer *jwt.Signer
}

func New(pool *pgxpool.Pool, rdb *redis.Client, signer *jwt.Signer) *Service {
    return &Service{
        pool:   pool,
        rdb:    rdb,
        signer: signer,
    }
}

type MintRequest struct {
    RetailerID  string
    ShopperRef  string
    Scopes      []string
    TTLSeconds  int
    IPAddress   string
}

type MintResult struct {
    AccessToken    string
    TokenType      string
    ExpiresIn      int
    ShopperTokenID string
}

func (s *Service) Mint(ctx context.Context, req MintRequest) (*MintResult, error) {
    if req.TTLSeconds <= 0 {
        return nil, errors.New("TTL must be positive")
    }
    if req.TTLSeconds > 3600 {
        return nil, errors.New("TTL cannot exceed 3600 seconds")
    }
    if req.ShopperRef == "" {
        return nil, errors.New("shopper_ref is required")
    }
    if len(req.Scopes) == 0 {
        return nil, errors.New("at least one scope is required")
    }

    accessToken, tokenID, expiresAt, err := s.signer.MintToken(req.RetailerID, req.ShopperRef, req.Scopes, req.TTLSeconds)
    if err != nil {
        return nil, fmt.Errorf("sign token: %w", err)
    }

    go func() {
        bgCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
        defer cancel()

        _, err := s.pool.Exec(bgCtx, `
            INSERT INTO auth.token_audit (token_id, retailer_id, shopper_ref, expires_at, scopes, ip_address)
            VALUES ($1, $2, $3, $4, $5, $6::inet)
        `, tokenID, req.RetailerID, req.ShopperRef, expiresAt, req.Scopes, req.IPAddress)
        if err != nil {
            fmt.Printf("WARN: failed to record token audit: %v\n", err)
        }
    }()

    return &MintResult{
        AccessToken:    accessToken,
        TokenType:      "Bearer",
        ExpiresIn:      req.TTLSeconds,
        ShopperTokenID: tokenID,
    }, nil
}

func (s *Service) Revoke(ctx context.Context, retailerID, shopperTokenID string) error {
    var expiresAt time.Time
    err := s.pool.QueryRow(ctx, `
        SELECT expires_at FROM auth.token_audit
        WHERE token_id = $1 AND retailer_id = $2 AND revoked_at IS NULL
    `, shopperTokenID, retailerID).Scan(&expiresAt)

    if err != nil {
        if errors.Is(err, pgx.ErrNoRows) {
            return ErrInvalidToken
        }
        return fmt.Errorf("query token: %w", err)
    }

    if time.Now().After(expiresAt) {
        return nil
    }

    _, err = s.pool.Exec(ctx, `
        UPDATE auth.token_audit SET revoked_at = NOW()
        WHERE token_id = $1 AND retailer_id = $2
    `, shopperTokenID, retailerID)
    if err != nil {
        return fmt.Errorf("update token audit: %w", err)
    }

    remaining := time.Until(expiresAt)
    if remaining > 0 {
        err = s.rdb.Set(ctx, "token:revoked:"+shopperTokenID, "1", remaining).Err()
        if err != nil {
            fmt.Printf("WARN: failed to cache token revocation: %v\n", err)
        }
    }

    return nil
}

func (s *Service) IsRevoked(ctx context.Context, shopperTokenID string) (bool, error) {
    val, err := s.rdb.Get(ctx, "token:revoked:"+shopperTokenID).Result()
    if err == nil && val == "1" {
        return true, nil
    }
    if err == redis.Nil {
        return false, nil
    }
    if err != nil {
        return false, fmt.Errorf("check revocation: %w", err)
    }
    return false, nil
}
