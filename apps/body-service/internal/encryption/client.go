package encryption

import (
    "crypto/aes"
    "crypto/cipher"
    "crypto/rand"
    "crypto/sha256"
    "encoding/base64"
    "errors"
    "fmt"
    "io"
    "os"
    "sync"
)

type Client struct {
    key []byte
    mu  sync.RWMutex
}

func New(keyPath string) (*Client, error) {
    keyBytes, err := os.ReadFile(keyPath)
    if err != nil {
        return nil, fmt.Errorf("read encryption key: %w", err)
    }

    hash := sha256.Sum256(keyBytes)
    return &Client{key: hash[:]}, nil
}

func (c *Client) Encrypt(plaintext []byte) ([]byte, error) {
    c.mu.RLock()
    defer c.mu.RUnlock()

    block, err := aes.NewCipher(c.key)
    if err != nil {
        return nil, fmt.Errorf("create cipher: %w", err)
    }

    gcm, err := cipher.NewGCM(block)
    if err != nil {
        return nil, fmt.Errorf("create gcm: %w", err)
    }

    nonce := make([]byte, gcm.NonceSize())
    if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
        return nil, fmt.Errorf("generate nonce: %w", err)
    }

    ciphertext := gcm.Seal(nonce, nonce, plaintext, nil)
    return ciphertext, nil
}

func (c *Client) Decrypt(ciphertext []byte) ([]byte, error) {
    c.mu.RLock()
    defer c.mu.RUnlock()

    block, err := aes.NewCipher(c.key)
    if err != nil {
        return nil, fmt.Errorf("create cipher: %w", err)
    }

    gcm, err := cipher.NewGCM(block)
    if err != nil {
        return nil, fmt.Errorf("create gcm: %w", err)
    }

    nonceSize := gcm.NonceSize()
    if len(ciphertext) < nonceSize {
        return nil, errors.New("ciphertext too short")
    }

    nonce, ciphertext := ciphertext[:nonceSize], ciphertext[nonceSize:]
    plaintext, err := gcm.Open(nil, nonce, ciphertext, nil)
    if err != nil {
        return nil, fmt.Errorf("decrypt: %w", err)
    }

    return plaintext, nil
}

func (c *Client) Fingerprint() string {
    hash := sha256.Sum256(c.key)
    return base64.RawURLEncoding.EncodeToString(hash[:])[:16]
}
