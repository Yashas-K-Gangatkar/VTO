# VTO — Universal Virtual Try-On SDK Platform

> Enterprise SDK + API platform that provides AI Virtual Try-On to clothing retailers. Drop our SDK into your existing iOS, Android, or Web app. Your customers scan their body once. They try on any garment from your catalog in under 3 seconds. You pay only when a try-on image is successfully generated and viewed.

## Status

**Phase:** Milestone 1 — Foundation
**Architecture:** Frozen (see `docs/decision-register.md`, decisions DR-001 through DR-085)
**License:** Proprietary (see `LICENSE`)

## Repository structure

```
vto/
├── apps/              # Deployable backend services (Go)
├── ai/                # AI engine (Python) — IDM-VTON, Triton, training
├── sdks/              # Retailer-facing SDKs (iOS, Android, Web, Flutter, RN)
├── dashboard/         # Retailer dashboard frontend (Next.js)
├── packages/          # Shared internal packages (contracts, types, error-codes)
├── infrastructure/    # Terraform, Docker, Kubernetes, scripts
├── docs/              # Architecture docs, ADRs, runbooks
├── tests/             # Cross-service tests (E2E, load, contract)
├── tools/             # Internal tooling (codegen, benchmarks, release)
└── .github/           # CI/CD workflows
```

## Quick start

### Prerequisites

- Go 1.22+
- Node.js 20+ (with pnpm 9+)
- Python 3.11+
- Docker + Docker Compose
- Make
- Terraform 1.7+ (for cloud deploys)

### Run the full stack locally

```bash
make dev
```

This starts Postgres, Redis, Kafka, ClickHouse, and all backend services via Docker Compose. Healthcheck at http://localhost:8080/v1/health.

### Common commands

```bash
make dev          # Start full local stack
make test         # Run all unit tests
make lint         # Lint all code
make build        # Build all services and packages
make migrate      # Apply DB migrations
make seed         # Seed local DB with test data
make clean        # Remove build artifacts
```

## Documentation

- [`docs/decision-register.md`](docs/decision-register.md) — 85 architectural decisions (DR-001 through DR-085)
- [`docs/architecture/`](docs/architecture/) — Architecture docs and ADRs
- [`docs/runbooks/`](docs/runbooks/) — Per-service on-call runbooks
- [`docs/onboarding/`](docs/onboarding/) — New engineer onboarding

## Architecture

The platform is a monorepo with 14 microservices. Backend services are in Go, AI engine in Python, dashboard in TypeScript, SDKs in platform-native languages. See `docs/architecture/overview.md` for the full system diagram and service interaction model.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). Trunk-based development, conventional commits, squash merge. All PRs require review and passing CI.

## Security

See [`SECURITY.md`](SECURITY.md). To report a vulnerability, email security@vto.example. Do not open public issues for security reports.

## License

Proprietary. See [`LICENSE`](LICENSE).
