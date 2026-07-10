package jwt

import (
    "crypto/rand"
    "crypto/rsa"
    "crypto/x509"
    "encoding/pem"
    "os"
    "path/filepath"
    "testing"
)

func generateTestKey(t *testing.T) (privatePath, publicPath string) {
    t.Helper()

    tmpDir := t.TempDir()
    privatePath = filepath.Join(tmpDir, "private.pem")
    publicPath = filepath.Join(tmpDir, "public.pem")

    privateKey, err := rsa.GenerateKey(rand.Reader, 2048)
    if err != nil {
        t.Fatalf("generate RSA key: %v", err)
    }

    privateDER := x509.MarshalPKCS1PrivateKey(privateKey)
    privatePEM := pem.EncodeToMemory(&pem.Block{
        Type:  "RSA PRIVATE KEY",
        Bytes: privateDER,
    })
    if err := os.WriteFile(privatePath, privatePEM, 0600); err != nil {
        t.Fatalf("write private key: %v", err)
    }

    publicDER, err := x509.MarshalPKIXPublicKey(&privateKey.PublicKey)
    if err != nil {
        t.Fatalf("marshal public key: %v", err)
    }
    publicPEM := pem.EncodeToMemory(&pem.Block{
        Type:  "PUBLIC KEY",
        Bytes: publicDER,
    })
    if err := os.WriteFile(publicPath, publicPEM, 0644); err != nil {
        t.Fatalf("write public key: %v", err)
    }

    return privatePath, publicPath
}

func TestSigner_MintAndVerify(t *testing.T) {
    privatePath, publicPath := generateTestKey(t)

    signer, err := NewSigner(privatePath, "test-key-1", "test-issuer", "test-audience")
    if err != nil {
        t.Fatalf("NewSigner: %v", err)
    }

    token, tokenID, expiresAt, err := signer.MintToken("ret-123", "shopper-456", []string{"body_scan", "tryon"}, 3600)
    if err != nil {
        t.Fatalf("MintToken: %v", err)
    }

    if token == "" {
        t.Error("expected non-empty token")
    }
    if tokenID == "" {
        t.Error("expected non-empty token ID")
    }
    if expiresAt.IsZero() {
        t.Error("expected non-zero expiry")
    }

    verifier, err := NewVerifier(publicPath, "test-key-1", "test-issuer", "test-audience")
    if err != nil {
        t.Fatalf("NewVerifier: %v", err)
    }

    claims, err := verifier.Verify(token)
    if err != nil {
        t.Fatalf("Verify: %v", err)
    }

    if claims.RetailerID != "ret-123" {
        t.Errorf("expected retailer_id 'ret-123', got %q", claims.RetailerID)
    }
    if claims.ShopperRef != "shopper-456" {
        t.Errorf("expected shopper_ref 'shopper-456', got %q", claims.ShopperRef)
    }
    if len(claims.Scopes) != 2 {
        t.Errorf("expected 2 scopes, got %d", len(claims.Scopes))
    }
    if claims.ID != tokenID {
        t.Errorf("expected token ID %q, got %q", tokenID, claims.ID)
    }
}

func TestVerifier_RejectsInvalidToken(t *testing.T) {
    _, publicPath := generateTestKey(t)

    verifier, err := NewVerifier(publicPath, "test-key-1", "test-issuer", "test-audience")
    if err != nil {
        t.Fatalf("NewVerifier: %v", err)
    }

    _, err = verifier.Verify("invalid.token.here")
    if err == nil {
        t.Error("expected error for invalid token, got nil")
    }
}

func TestToJWKS(t *testing.T) {
    _, publicPath := generateTestKey(t)

    verifier, err := NewVerifier(publicPath, "test-key-1", "test-issuer", "test-audience")
    if err != nil {
        t.Fatalf("NewVerifier: %v", err)
    }

    jwks := ToJWKS(verifier.PublicKey(), verifier.KeyID())

    if len(jwks.Keys) != 1 {
        t.Fatalf("expected 1 key, got %d", len(jwks.Keys))
    }

    key := jwks.Keys[0]
    if key.KTY != "RSA" {
        t.Errorf("expected kty 'RSA', got %q", key.KTY)
    }
    if key.KID != "test-key-1" {
        t.Errorf("expected kid 'test-key-1', got %q", key.KID)
    }
    if key.Use != "sig" {
        t.Errorf("expected use 'sig', got %q", key.Use)
    }
    if key.Alg != "RS256" {
        t.Errorf("expected alg 'RS256', got %q", key.Alg)
    }
    if key.N == "" {
        t.Error("expected non-empty modulus")
    }
    if key.E == "" {
        t.Error("expected non-empty exponent")
    }
}
