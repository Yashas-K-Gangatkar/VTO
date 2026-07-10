package main

import (
    "context"
    "flag"
    "fmt"
    "os"
    "time"

    "github.com/google/uuid"
    "github.com/rs/zerolog"
    "github.com/rs/zerolog/log"

    "github.com/vto/auth-service/internal/apikey"
    "github.com/vto/auth-service/internal/config"
    "github.com/vto/auth-service/internal/database"
)

func main() {
    zerolog.TimeFieldFormat = time.RFC3339Nano
    log.Logger = log.Output(os.Stdout).With().Str("service", "create-api-key").Logger()

    retailerIDStr := flag.String("retailer-id", "", "Retailer UUID (required)")
    name := flag.String("name", "Initial API key", "API key name")
    scopesStr := flag.String("scopes", "server_to_server", "Comma-separated scopes")
    flag.Parse()

    if *retailerIDStr == "" {
        fmt.Fprintln(os.Stderr, "Error: -retailer-id is required")
        os.Exit(1)
    }

    retailerID, err := uuid.Parse(*retailerIDStr)
    if err != nil {
        log.Fatal().Err(err).Msg("invalid retailer UUID")
    }

    cfg, err := config.Load()
    if err != nil {
        log.Fatal().Err(err).Msg("failed to load config")
    }

    pool, err := database.New(cfg.DatabaseURL)
    if err != nil {
        log.Fatal().Err(err).Msg("failed to connect to database")
    }
    defer pool.Close()

    var scopes []string
    for _, s := range splitScopes(*scopesStr) {
        scopes = append(scopes, s)
    }

    svc := apikey.New(pool)
    // Use a context with the retailer_id set so RLS works
    ctx := context.Background()
    fullKey, err := svc.CreateWithoutRLS(ctx, retailerID, *name, scopes, nil)
    if err != nil {
        log.Fatal().Err(err).Msg("failed to create API key")
    }

    fmt.Println("API key created successfully:")
    fmt.Printf("  ID:       %s\n", fullKey.ID)
    fmt.Printf("  Retailer: %s\n", fullKey.RetailerID)
    fmt.Printf("  Name:     %s\n", fullKey.Name)
    fmt.Printf("  Prefix:   %s\n", fullKey.KeyPrefix)
    fmt.Printf("  Scopes:   %v\n", fullKey.Scopes)
    fmt.Println()
    fmt.Println("  FULL KEY (save this — it will not be shown again):")
    fmt.Printf("  %s\n", fullKey.Key)
}

func splitScopes(s string) []string {
    var scopes []string
    start := 0
    for i, c := range s {
        if c == ',' {
            scopes = append(scopes, trimSpaces(s[start:i]))
            start = i + 1
        }
    }
    scopes = append(scopes, trimSpaces(s[start:]))
    return scopes
}

func trimSpaces(s string) string {
    start := 0
    for start < len(s) && (s[start] == ' ' || s[start] == '\t') {
        start++
    }
    end := len(s)
    for end > start && (s[end-1] == ' ' || s[end-1] == '\t') {
        end--
    }
    return s[start:end]
}
