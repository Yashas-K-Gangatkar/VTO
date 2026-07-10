# New Engineer Onboarding

Welcome. This guide gets you from `git clone` to first PR in under an hour.

## 30 minutes: Get the stack running

### Prerequisites

Install on your machine:
- **Go 1.22+**: https://go.dev/dl/
- **Node.js 20+ and pnpm 9+**: https://nodejs.org/ then `npm install -g pnpm`
- **Docker Desktop**: https://www.docker.com/products/docker-desktop/
- **Postgres client** (for `psql`): `brew install libpq` on macOS
- **Make**: built-in on Linux/macOS; on Windows use WSL2
- **Terraform 1.7+** (only if you'll work on infra): https://developer.hashicorp.com/terraform/downloads

### Clone and install

```bash
git clone <repo-url>
cd vto
make install
```

This installs:
- pnpm workspace dependencies
- Go module dependencies for all services
- Python dependencies for AI engine (if `ai/pyproject.toml` exists)

### Start the local stack

```bash
make dev
```

This starts via Docker Compose:
- Postgres (port 5432)
- Redis (port 6379)
- Kafka (port 29092) + Kafka UI (port 8088)
- ClickHouse HTTP (port 8123) and native (port 9000)
- MinIO console (port 9001) and S3 API (port 9444)
- All backend services (port 8080+)

Wait ~30 seconds for everything to be ready.

### Verify

```bash
curl http://localhost:8080/v1/health
# Expected: {"status":"ok","version":"0.1.0-dev",...}
```

### Seed test data

```bash
make seed
```

This creates:
- 1 dev retailer
- 1 dashboard user (`admin@dev-retailer.example`)
- 10 sample SKUs (`DEV-SKU-001` through `DEV-SKU-010`)
- Pricing tier + webhook endpoint

## Next 30 minutes: Understand the codebase

### Read these (in order)

1. **[README.md](../../README.md)** — repo overview
2. **[docs/decision-register.md](../decision-register.md)** — the 85 architectural decisions. This is the constitutional law. Read at least DR-001 through DR-030.
3. **[docs/architecture/](../architecture/README.md)** — architecture docs and ADRs
4. **The api-gateway source** at `apps/api-gateway/` — this is the template for all Go services. Read it end-to-end.

### Understand the structure

```
apps/         # 12 backend services (Go)
ai/           # AI engine (Python)
sdks/         # Retailer SDKs (iOS, Android, Web)
dashboard/    # Retailer dashboard (Next.js)
packages/     # Shared packages (contracts, types, error-codes)
infrastructure/ # Docker, Terraform, K8s, scripts
docs/         # This directory
tests/        # Cross-service tests
tools/        # Internal tooling
```

### Common commands

```bash
make dev        # Start full stack
make test       # Run all unit tests
make lint       # Lint everything
make build      # Build all services
make fmt        # Format code
make migrate    # Apply DB migrations
make seed       # Seed test data
make clean      # Remove build artifacts
```

## Your first PR

### Pick a starter issue

Look for issues labeled `good-first-issue` in the issue tracker. Typical starters:
- Add a missing test to an existing handler
- Add a new field to a response (with test + doc update)
- Fix a typo or clarify a doc
- Add a health-check dependency (e.g., ping Postgres in auth-service's `/health`)

### Branch

```bash
git checkout -b feat/<short-description>
```

### Code

Follow:
- [.editorconfig](../../.editorconfig) — indentation, line endings
- [CONTRIBUTING.md](../../CONTRIBUTING.md) — branch strategy, commits, PRs
- The patterns in `apps/api-gateway/` — the template

### Test

```bash
make test
make lint
```

Both must pass before pushing.

### Commit (Conventional Commits)

```bash
git add .
git commit -m "feat(auth-service): add Postgres ping to health check"
```

### Push and open PR

```bash
git push -u origin feat/<short-description>
```

Open a PR. CI runs automatically. Request review from a teammate (see CODEOWNERS).

## What to read next

After your first PR, deepen your understanding:

1. **[docs/retailer-integration-blueprint.md](../retailer-integration-blueprint.md)** — what we're building from the retailer's perspective
2. **[docs/ai-engine-architecture.md](../ai-engine-architecture.md)** — the AI engine (if you'll touch AI code)
3. **[docs/implementation-blueprint.md](../implementation-blueprint.md)** — the 100-task roadmap
4. **[docs/architecture/adr/](../architecture/adr/)** — ADRs for specific decisions

## Get unstuck

- **Slack:** `#vto-eng` (engineering channel)
- **Pairing:** Ask in `#vto-eng` — anyone will pair with you
- **On-call:** See `docs/runbooks/` for service-specific debugging
- **Architecture questions:** Ask in `#vto-architecture`

Welcome aboard.
