package jwt

import (
    "crypto/rsa"
    "encoding/base64"
    "math/big"
)

type JWK struct {
    KTY string `json:"kty"`
    KID string `json:"kid"`
    Use string `json:"use"`
    Alg string `json:"alg"`
    N   string `json:"n"`
    E   string `json:"e"`
}

type JWKS struct {
    Keys []JWK `json:"keys"`
}

func ToJWKS(pubKey *rsa.PublicKey, keyID string) JWKS {
    return JWKS{
        Keys: []JWK{
            {
                KTY: "RSA",
                KID: keyID,
                Use: "sig",
                Alg: "RS256",
                N:   base64.RawURLEncoding.EncodeToString(pubKey.N.Bytes()),
                E:   base64.RawURLEncoding.EncodeToString(big.NewInt(int64(pubKey.E)).Bytes()),
            },
        },
    }
}
