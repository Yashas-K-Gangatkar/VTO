# Terraform

All infrastructure as code. No manual AWS changes allowed in staging or production (DR-077).

## Structure

```
terraform/
├── modules/          # Reusable, environment-agnostic modules
│   ├── vpc/
│   ├── ecs/
│   ├── rds/
│   ├── elasticache/
│   ├── msk/
│   ├── s3/
│   ├── cloudfront/
│   ├── kms/
│   ├── waf/
│   ├── gpu-pool/
│   └── iam/
├── environments/     # Environment-specific composition
│   ├── dev/          # Single-AZ, minimal
│   ├── staging/      # Multi-AZ, smaller scale
│   └── production/   # Multi-AZ, multi-region
└── README.md (this file)
```

## Usage

### Local dev

Dev environment is docker-compose, not Terraform. See `infrastructure/docker/`.

### Staging / production

```bash
cd environments/staging  # or production

# Initialize (state in S3 + DynamoDB lock)
terraform init \
  -backend-config="bucket=vto-tfstate" \
  -backend-config="key=staging/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=vto-tfstate-lock"

# Plan
terraform plan -out=tfplan

# Apply (requires approval)
terraform apply tfplan
```

## State management

- State in S3 (`vto-tfstate` bucket, one key per environment per region)
- Locking via DynamoDB (`vto-tfstate-lock` table)
- State access restricted to CI/CD IAM role (no human access)
- Drift detection: `terraform plan` runs nightly in CI; alerts on drift

## Secrets

- No secrets in `.tf` files or `.tfvars`
- Secrets in AWS Secrets Manager, referenced via `data.aws_secretsmanager_secret`
- Terraform reads/writes secret *references*, never secret *values*
- `*.tfvars` files gitignored; `*.tfvars.example` committed

## Modules

Each module is self-contained with:
- `main.tf` — resources
- `variables.tf` — inputs
- `outputs.tf` — outputs
- `README.md` — usage docs

## Adding a new environment

1. Copy `environments/staging/` to `environments/<name>/`
2. Update `backend-config` key in init script
3. Update `terraform.tfvars` with environment-specific values
4. Run `terraform init && terraform plan`

## Drift policy

If `terraform plan` shows drift:
1. **Investigate** — who made the manual change and why?
2. **Either** import the change into Terraform (if intentional) **or** revert it via AWS console
3. **Document** the incident in `docs/architecture/adr/`

Manual changes are not "wrong" — sometimes they're emergencies. But they MUST be backfilled into Terraform within 7 days.
