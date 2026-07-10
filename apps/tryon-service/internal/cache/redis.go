package cache

import (
    "context"
    "encoding/json"
    "fmt"
    "time"

    "github.com/redis/go-redis/v9"
)

type Redis struct {
    rdb *redis.Client
}

func New(redisURL string) (*Redis, error) {
    opt, err := redis.ParseURL(redisURL)
    if err != nil {
        return nil, fmt.Errorf("parse redis url: %w", err)
    }

    rdb := redis.NewClient(opt)

    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()
    if err := rdb.Ping(ctx).Err(); err != nil {
        return nil, fmt.Errorf("ping redis: %w", err)
    }

    return &Redis{rdb: rdb}, nil
}

func (r *Redis) GetTryOn(ctx context.Context, cacheKey string) (*CachedTryOn, error) {
    val, err := r.rdb.Get(ctx, "tryon:cache:"+cacheKey).Result()
    if err == redis.Nil {
        return nil, nil
    }
    if err != nil {
        return nil, fmt.Errorf("get from cache: %w", err)
    }

    var cached CachedTryOn
    if err := json.Unmarshal([]byte(val), &cached); err != nil {
        return nil, fmt.Errorf("unmarshal cached tryon: %w", err)
    }

    return &cached, nil
}

func (r *Redis) SetTryOn(ctx context.Context, cacheKey string, tryon *CachedTryOn, ttl time.Duration) error {
    data, err := json.Marshal(tryon)
    if err != nil {
        return fmt.Errorf("marshal tryon: %w", err)
    }

    if err := r.rdb.Set(ctx, "tryon:cache:"+cacheKey, data, ttl).Err(); err != nil {
        return fmt.Errorf("set in cache: %w", err)
    }

    return nil
}

func (r *Redis) IsViewed(ctx context.Context, tryonID string) (bool, error) {
    val, err := r.rdb.Get(ctx, "tryon:dedup:"+tryonID).Result()
    if err == redis.Nil {
        return false, nil
    }
    if err != nil {
        return false, fmt.Errorf("check dedup: %w", err)
    }
    return val == "1", nil
}

func (r *Redis) MarkViewed(ctx context.Context, tryonID string, ttl time.Duration) error {
    if err := r.rdb.Set(ctx, "tryon:dedup:"+tryonID, "1", ttl).Err(); err != nil {
        return fmt.Errorf("mark viewed: %w", err)
    }
    return nil
}

type CachedTryOn struct {
    TryOnID      string `json:"tryon_id"`
    ImageURL     string `json:"image_url"`
    ThumbnailURL string `json:"thumbnail_url"`
    QualityScore float64 `json:"quality_score"`
    ModelVersion string `json:"model_version"`
    RenderTimeMs int    `json:"render_time_ms"`
}

func (r *Redis) Close() error {
    return r.rdb.Close()
}
