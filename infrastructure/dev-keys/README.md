# Dev signing keys for JWT (DO NOT USE IN PRODUCTION)

These keys are for local development only. Production uses AWS KMS-managed keys.

## Generate fresh keys

```bash
cd infrastructure/dev-keys
openssl genrsa -out jwt-private.pem 2048
openssl rsa -in jwt-private.pem -pubout -out jwt-public.pem
chmod 600 jwt-private.pem
```

## Add to .gitignore (already done)

`*.pem` is gitignored. These keys must never be committed.

## Why this exists

The auth-service needs RSA keys to sign JWTs locally. In production, keys are
stored in AWS KMS and the service fetches them via IAM role.
