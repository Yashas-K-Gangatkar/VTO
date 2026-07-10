package jwt

import (
    "crypto/rsa"
    "crypto/sha256"
    "crypto/x509"
    "encoding/hex"
    "encoding/pem"
    "errors"
    "fmt"
    "os"
    "time"

    "github.com/golang-jwt/jwt/v5"
    "github.com/google/uuid"
)

type Claims struct {
    RetailerID string   `json:"retailer_id"`
    ShopperRef string   `json:"shopper_ref"`
    Scopes     []string `json:"scopes"`
    jwt.RegisteredClaims
}

type Signer struct {
    privateKey *rsa.PrivateKey
    keyID      string
    issuer     string
    audience   string
}

func NewSigner(privateKeyPath, keyID, issuer, audience string) (*Signer, error) {
    keyBytes, err := os.ReadFile(privateKeyPath)
    if err != nil {
        return nil, fmt.Errorf("read private key: %w", err)
    }

    block, _ := pem.Decode(keyBytes)
    if block == nil {
        return nil, errors.New("failed to decode PEM block from private key")
    }

    privateKey, err := x509.ParsePKCS1PrivateKey(block.Bytes)
    if err != nil {
        key, err2 := x509.ParsePKCS8PrivateKey(block.Bytes)
        if err2 != nil {
            return nil, fmt.Errorf("parse private key: %w / %w", err, err2)
        }
        rsaKey, ok := key.(*rsa.PrivateKey)
        if !ok {
            return nil, errors.New("private key is not RSA")
        }
        privateKey = rsaKey
    }

    return &Signer{
        privateKey: privateKey,
        keyID:      keyID,
        issuer:     issuer,
        audience:   audience,
    }, nil
}

func (s *Signer) MintToken(retailerID, shopperRef string, scopes []string, ttlSeconds int) (token string, tokenID string, expiresAt time.Time, err error) {
    tokenID = "st_" + uuid.New().String()
    expiresAt = time.Now().Add(time.Duration(ttlSeconds) * time.Second)

    claims := Claims{
        RetailerID: retailerID,
        ShopperRef: shopperRef,
        Scopes:     scopes,
        RegisteredClaims: jwt.RegisteredClaims{
            ID:        tokenID,
            Issuer:    s.issuer,
            Audience:  jwt.ClaimStrings{s.audience},
            Subject:   shopperRef,
            IssuedAt:  jwt.NewNumericDate(time.Now()),
            ExpiresAt: jwt.NewNumericDate(expiresAt),
        },
    }

    t := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
    t.Header["kid"] = s.keyID

    token, err = t.SignedString(s.privateKey)
    if err != nil {
        return "", "", time.Time{}, fmt.Errorf("sign token: %w", err)
    }

    return token, tokenID, expiresAt, nil
}

type Verifier struct {
    publicKey *rsa.PublicKey
    keyID     string
    issuer    string
    audience  string
}

func NewVerifier(publicKeyPath, keyID, issuer, audience string) (*Verifier, error) {
    keyBytes, err := os.ReadFile(publicKeyPath)
    if err != nil {
        return nil, fmt.Errorf("read public key: %w", err)
    }

    block, _ := pem.Decode(keyBytes)
    if block == nil {
        return nil, errors.New("failed to decode PEM block from public key")
    }

    publicKey, err := x509.ParsePKIXPublicKey(block.Bytes)
    if err != nil {
        pub, err2 := x509.ParsePKCS1PublicKey(block.Bytes)
        if err2 != nil {
            return nil, fmt.Errorf("parse public key: %w / %w", err, err2)
        }
        publicKey = pub
    }

    rsaPub, ok := publicKey.(*rsa.PublicKey)
    if !ok {
        return nil, errors.New("public key is not RSA")
    }

    return &Verifier{
        publicKey: rsaPub,
        keyID:     keyID,
        issuer:    issuer,
        audience:  audience,
    }, nil
}

func (v *Verifier) Verify(tokenString string) (*Claims, error) {
    claims := &Claims{}

    token, err := jwt.ParseWithClaims(tokenString, claims, func(t *jwt.Token) (interface{}, error) {
        if _, ok := t.Method.(*jwt.SigningMethodRSA); !ok {
            return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
        }
        return v.publicKey, nil
    })

    if err != nil {
        return nil, fmt.Errorf("parse token: %w", err)
    }

    if !token.Valid {
        return nil, errors.New("invalid token")
    }

    if claims.Issuer != v.issuer {
        return nil, fmt.Errorf("invalid issuer: expected %s, got %s", v.issuer, claims.Issuer)
    }

    if len(claims.Audience) == 0 || claims.Audience[0] != v.audience {
        return nil, fmt.Errorf("invalid audience: expected %s", v.audience)
    }

    return claims, nil
}

func (v *Verifier) PublicKey() *rsa.PublicKey {
    return v.publicKey
}

func (v *Verifier) KeyID() string {
    return v.keyID
}

func (v *Verifier) Fingerprint() string {
    der, err := x509.MarshalPKIXPublicKey(v.publicKey)
    if err != nil {
        return "unknown"
    }
    hash := sha256.Sum256(der)
    return hex.EncodeToString(hash[:])[:16]
}
