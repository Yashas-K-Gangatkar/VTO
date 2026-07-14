package s3

import (
    "bytes"
    "context"
    "fmt"
    "io"
    "net/url"
    "time"

    "github.com/aws/aws-sdk-go-v2/aws"
    "github.com/aws/aws-sdk-go-v2/credentials"
    awss3 "github.com/aws/aws-sdk-go-v2/service/s3"
)

type Client struct {
    s3     *awss3.Client
    bucket string
}

func New(endpoint, accessKey, secretKey, bucket, region string) (*Client, error) {
    if endpoint != "" {
        _, err := url.Parse(endpoint)
        if err != nil {
            return nil, fmt.Errorf("parse s3 endpoint: %w", err)
        }
    }

    client := awss3.New(awss3.Options{
        Region:       region,
        BaseEndpoint: aws.String(endpoint),
        UsePathStyle: true,
        Credentials:  credentials.NewStaticCredentialsProvider(accessKey, secretKey, ""),
    })

    return &Client{s3: client, bucket: bucket}, nil
}

func (c *Client) PutObject(ctx context.Context, key string, data []byte, contentType string) error {
    _, err := c.s3.PutObject(ctx, &awss3.PutObjectInput{
        Bucket:      aws.String(c.bucket),
        Key:         aws.String(key),
        Body:        bytes.NewReader(data),
        ContentType: aws.String(contentType),
    })
    if err != nil {
        return fmt.Errorf("put object: %w", err)
    }
    return nil
}

func (c *Client) GetObject(ctx context.Context, key string) ([]byte, error) {
    resp, err := c.s3.GetObject(ctx, &awss3.GetObjectInput{
        Bucket: aws.String(c.bucket),
        Key:    aws.String(key),
    })
    if err != nil {
        return nil, fmt.Errorf("get object: %w", err)
    }
    defer resp.Body.Close()

    data, err := io.ReadAll(resp.Body)
    if err != nil {
        return nil, fmt.Errorf("read body: %w", err)
    }

    return data, nil
}

func (c *Client) DeleteObject(ctx context.Context, key string) error {
    _, err := c.s3.DeleteObject(ctx, &awss3.DeleteObjectInput{
        Bucket: aws.String(c.bucket),
        Key:    aws.String(key),
    })
    if err != nil {
        return fmt.Errorf("delete object: %w", err)
    }
    return nil
}

func (c *Client) GenerateKey(retailerID, profileID string) string {
    return fmt.Sprintf("%s/%s.enc", retailerID, profileID)
}

func (c *Client) PresignedGetURL(ctx context.Context, key string, expiry time.Duration) (string, error) {
    presignClient := awss3.NewPresignClient(c.s3)
    req, err := presignClient.PresignGetObject(ctx, &awss3.GetObjectInput{
        Bucket: aws.String(c.bucket),
        Key:    aws.String(key),
    }, awss3.WithPresignExpires(expiry))
    if err != nil {
        return "", fmt.Errorf("presign: %w", err)
    }
    return req.URL, nil
}
