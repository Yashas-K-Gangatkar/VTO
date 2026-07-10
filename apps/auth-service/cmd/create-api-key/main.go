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
        fmt.Fprintln(os.Stderr, "")
        fmt.Fprintln(os.Stderr, "Usage: create-api-key -retailer-id <uuid> [-name 'Key name'] [-scopes 'scope1,scope2']")
        os.Exit(1)
    }

    retailerID, err := uuid.Parse(*retailerIDStr)
    if err != nil {
        log.Fatal().Err(err).Str("retailer_id", *retailerIDStr).Msg("invalid retailer UUID")
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
    fullKey, err := svc.Create(context.Background(), retailerID, *name, scopes, nil)
    if err != nil {
        log.Fatal().Err(err).Msg("failed to create API key")
    }

    fmt.Println("API key created successfully:")
    fmt.Println()
    fmt.Printf("  ID:       %s\n", fullKey.ID)
    fmt.Printf("  Retailer: %s\n", fullKey.RetailerID)
    fmt.Printf("  Name:     %s\n", fullKey.Name)
    fmt.Printf("  Prefix:   %s\n", fullKey.KeyPrefix)
    fmt.Printf("  Scopes:   %v\n", fullKey.Scopes)
    fmt.Printf("  Created:  %s\n", fullKey.CreatedAt.Format(time.RFC3339))
    fmt.Println()
    fmt.Println("  FULL KEY (save this — it will not be shown again):")
    fmt.Println()
    fmt.Printf("  %s\n", fullKey.Key)
    fmt.Println()
    fmt.Println("Store this key securely. It will be needed for server-to-server API calls.")
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
