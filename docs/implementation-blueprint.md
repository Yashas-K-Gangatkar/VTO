# Production Implementation Blueprint v1.0
## VTO Enterprise SDK Platform — Repo Readiness & Implementation Plan

**Document type:** Production implementation blueprint
**Author:** Principal Software Architect / Tech Lead
**Date:** 2026-07-10
**Status:** Architecture FROZEN. Implementation planning only.
**Mode:** Pure engineering execution. No redesign. No business.

> **Mission:** Transform the VTO repository into a production-ready enterprise codebase capable of $100M ARR scale. Every artifact in this document is implementable by a competent engineering team starting tomorrow.

---

# Table of Contents

1. Repository Audit (framework + severity rubric)
2. Repository Structure (final folder tree)
3. Microservice Design (14 services, full specs)
4. Database Design (Postgres, Redis, S3/R2, queues)
5. API Specification (OpenAPI-style, all endpoints)
6. SDK Design (iOS, Android, Web, Flutter, React Native)
7. AI Service Design
8. Infrastructure (Docker, K8s, Terraform, CI/CD)
9. Coding Standards
10. Development Roadmap (5 milestones)
11. First 100 Engineering Tasks (execution order)
12. Decision Register update

---

# 1. Repository Audit

## Honest disclosure

I cannot directly access `https://github.com/Yashas-K-Gangatkar/VTO` from this environment. The audit below is a **checklist the team must execute** against the live repo. It's calibrated to the frozen architecture (DR-001 through DR-070) and to enterprise production standards (Google/Stripe/Apple/NVIDIA).

## Audit dimensions

Run each dimension against the repo. Score 0-3 per dimension:
- 0 = missing
- 1 = present but inadequate
- 2 = adequate
- 3 = exemplary

### 1.1 Folder organization
- [ ] Monorepo vs polyrepo decision documented
- [ ] Clear separation: backend / frontend / SDK / AI / infra / docs
- [ ] No circular dependencies between top-level folders
- [ ] Naming convention consistent (kebab-case or snake_case throughout)
- [ ] No orphaned or duplicate folders

### 1.2 Package / dependency hygiene
- [ ] All dependency manifests version-pinned (`package-lock.json`, `poetry.lock`, `go.sum`, `Cargo.lock`)
- [ ] No `>=` or `*` version specifiers in production deps
- [ ] License file present for every dependency (or SBOM generated)
- [ ] No known CVEs (`npm audit`, `pip-audit`, `govulncheck` pass clean)
- [ ] Dev dependencies separated from production
- [ ] No unused dependencies (`depcheck`, `pipdeptree`)

### 1.3 Build configuration
- [ ] Reproducible builds (same input → same artifact hash)
- [ ] Build cached (Bazel, Turborepo, nx, or equivalent)
- [ ] Build works on clean machine with single command
- [ ] Build artifacts versioned and signed (SLSA Level 3 target)
- [ ] No hardcoded paths or environment-specific values

### 1.4 Architecture conformance
- [ ] Service boundaries match Section 3 of this document
- [ ] No shared databases between services (DR-008 schema-per-tenant respected)
- [ ] No synchronous service-to-service chains >2 hops
- [ ] Async communication via message queue where appropriate
- [ ] API gateway is the only public entry point

### 1.5 Code quality
- [ ] Linters configured and enforced in CI (ESLint, ruff, golangci-lint, SwiftLint, ktlint)
- [ ] Formatters configured and enforced (Prettier, Black, gofmt, swift-format)
- [ ] Type checking strict (TypeScript strict, mypy --strict, Go vet)
- [ ] No `any` types in TypeScript; no `interface{}` escapes in Go
- [ ] Test coverage ≥ 70% on business logic
- [ ] No `console.log` / `print` in production code (use structured logger)

### 1.6 Scalability
- [ ] Stateless services (no in-process state)
- [ ] Horizontal scaling tested (verified by load test)
- [ ] Database connection pooling configured
- [ ] Caching layer present (Redis) for hot reads
- [ ] Queue-based decoupling for long-running work (try-on, digitization)
- [ ] GPU pool autoscaling on queue depth (DR-060)

### 1.7 Security
- [ ] No secrets in code or config (use Vault / AWS Secrets Manager / Doppler)
- [ ] `.env.example` present; `.env` gitignored
- [ ] All APIs require authentication except `/health`
- [ ] Rate limiting configured (DR-027, DR-040)
- [ ] Input validation on every endpoint (Zod, Pydantic, validator)
- [ ] SQL injection prevention (parameterized queries, no string concat)
- [ ] OWASP Top 10 review completed
- [ ] SAST (Snyk, Semgrep) and DAST (ZAP) in CI

### 1.8 Maintainability
- [ ] Every service has a README
- [ ] Every public API has a docstring / JSDoc
- [ ] Architecture Decision Records (ADRs) folder present
- [ ] On-call runbook for each service
- [ ] Code review required (branch protection on `main`)
- [ ] No PRs > 400 lines (enforced by Danger / review bot)

### 1.9 Developer experience
- [ ] `make dev` or equivalent starts full stack locally
- [ ] Hot reload for all services
- [ ] Seed data script for local DB
- [ ] Postman / Bruno collection for API testing
- [ ] SDK sample apps for iOS, Android, Web
- [ ] Onboarding doc: new engineer productive in <1 day

## Severity rubric

| Severity | Definition | Action |
|----------|------------|--------|
| **S0 — Blocker** | Architecture violation, security hole, or production-breaking defect | Must fix before any production deploy |
| **S1 — Critical** | Will cause incidents or block scale | Must fix before pilot retailer launch |
| **S2 — Major** | Will cause maintenance pain or technical debt | Must fix within 90 days |
| **S3 — Minor** | Code smell or polish issue | Fix opportunistically |

## Audit output template

The team should produce:

```
REPO AUDIT — VTO
Date: __________
Auditor: __________

DIMENSION SCORES:
1.1 Folder organization: __/3
1.2 Package hygiene:       __/3
1.3 Build config:          __/3
1.4 Architecture:          __/3
1.5 Code quality:          __/3
1.6 Scalability:           __/3
1.7 Security:              __/3
1.8 Maintainability:       __/3
1.9 Developer experience:  __/3
                          ────
TOTAL:                    __/27

ISSUE LOG:
| ID | Severity | Dimension | Description | Fix estimate |
|----|----------|-----------|-------------|--------------|
| 1  | S0       | 1.7       | Hardcoded AWS key in `config.py` | 1h |
| 2  | S1       | 1.6       | No connection pooling in inference service | 4h |
| ...|          |           |             |              |

VERDICT:
- [ ] Production-ready
- [ ] Ready for pilot with caveats: __________
- [ ] Not ready; blockers: __________
```

## What I expect to find (predictions)

Based on typical early-stage repos, I expect:

1. **Monorepo without tooling** — likely a single repo with multiple folders but no Turborepo/Bazel/nx coordination
2. **Mixed languages without separation** — Python AI code co-mingled with TypeScript backend
3. **No service boundaries** — likely a monolith with API routes scattered
4. **`requirements.txt` with unpinned deps** — reproducibility nightmare
5. **No Docker or partial Docker** — local dev requires manual setup
6. **No CI/CD** — or a basic GitHub Action that just runs tests
7. **Hardcoded secrets in `.env` committed to repo** — security incident waiting to happen
8. **No tests** — or tests that don't actually test business logic
9. **No SDK extraction** — frontend code likely copy-pasted into sample apps
10. **No Terraform** — infrastructure manually provisioned

If any of these are true, they're S0 or S1 and must be fixed before Milestone 1 ends.

---

# 2. Repository Structure

## Decision: Monorepo with Turborepo

**Why monorepo:**
- Cross-service refactors are common (API contract changes touch backend + SDKs + docs)
- Shared types between backend, SDK, and dashboard
- Single source of truth for CI/CD, versioning, releases
- Easier onboarding (one clone, one build)

**Why Turborepo (not Bazel, not nx):**
- Bazel is overkill for our team size; operational tax unjustified
- nx is JS-only; we have Go, Python, Swift, Kotlin
- Turborepo handles multi-language workspaces with task graph caching

## Final folder structure

```
vto/                                              # Repo root
├── .github/
│   ├── workflows/                                # CI/CD pipelines
│   │   ├── ci.yml                                # PR checks (lint, test, build)
│   │   ├── deploy-staging.yml                    # Staging deploy on merge to main
│   │   ├── deploy-production.yml                 # Production deploy on tag
│   │   ├── security-scan.yml                     # Snyk + Semgrep + ZAP
│   │   ├── sbom.yml                              # SBOM generation
│   │   └── release.yml                           # SDK releases to registries
│   ├── CODEOWNERS                                # Per-folder ownership
│   └── PULL_REQUEST_TEMPLATE.md
│
├── apps/                                         # Deployable services (long-running processes)
│   ├── api-gateway/                              # Edge: routing, auth, rate limit
│   │   ├── src/
│   │   ├── Dockerfile
│   │   ├── README.md
│   │   └── package.json                          # TypeScript / Node
│   ├── auth-service/                             # Token issuance, validation
│   │   ├── src/
│   │   ├── Dockerfile
│   │   └── go.mod                                # Go
│   ├── body-service/                             # Body profile CRUD + SMPL-X storage
│   │   ├── src/
│   │   ├── Dockerfile
│   │   └── go.mod
│   ├── garment-service/                          # Catalog CRUD + digitization status
│   │   ├── src/
│   │   ├── Dockerfile
│   │   └── go.mod
│   ├── tryon-service/                            # Try-on job orchestration
│   │   ├── src/
│   │   ├── Dockerfile
│   │   └── go.mod
│   ├── inference-gateway/                        # GPU pool manager + Triton client
│   │   ├── src/
│   │   ├── Dockerfile
│   │   └── go.mod
│   ├── analytics-service/                        # Event ingestion → ClickHouse
│   │   ├── src/
│   │   ├── Dockerfile
│   │   └── go.mod
│   ├── billing-service/                          # Usage metering + Stripe integration
│   │   ├── src/
│   │   ├── Dockerfile
│   │   └── go.mod
│   ├── webhook-service/                          # Outbound webhook delivery + retries
│   │   ├── src/
│   │   ├── Dockerfile
│   │   └── go.mod
│   ├── notification-service/                     # Email + dashboard alerts
│   │   ├── src/
│   │   ├── Dockerfile
│   │   └── go.mod
│   ├── admin-service/                            # Internal admin API
│   │   ├── src/
│   │   ├── Dockerfile
│   │   └── go.mod
│   └── dashboard-api/                            # Retailer dashboard backend (BFF)
│       ├── src/
│       ├── Dockerfile
│       └── package.json                          # TypeScript
│
├── ai/                                           # AI engine (Python)
│   ├── inference/                                # Inference pipeline code
│   │   ├── pipelines/
│   │   │   ├── tryon_pipeline.py                 # Full try-on orchestration
│   │   │   ├── digitization_pipeline.py          # Garment digitization
│   │   │   └── body_scan_pipeline.py             # Body scan → SMPL-X
│   │   ├── models/                               # Model wrappers (Triton clients)
│   │   │   ├── idm_vton.py
│   │   │   ├── sam_garment.py
│   │   │   ├── openpose.py
│   │   │   ├── arcface.py
│   │   │   ├── densepose.py
│   │   │   ├── depth_anything.py
│   │   │   ├── codeformer.py
│   │   │   └── clip_scorer.py
│   │   ├── optimizers/                           # TensorRT, LCM, quantization
│   │   │   ├── tensorrt_compiler.py
│   │   │   ├── lcm_lora.py
│   │   │   └── fp16_converter.py
│   │   └── server.py                             # Triton model repo + launcher
│   ├── training/                                 # Fine-tuning scripts
│   │   ├── base_finetune.py                      # Full fine-tune (DR-053)
│   │   ├── lora_finetune.py                      # Per-retailer LoRA (DR-051)
│   │   ├── qlora_finetune.py                     # QLoRA fallback
│   │   └── data_preparation.py
│   ├── datasets/                                 # Dataset management (code, not data)
│   │   ├── loaders/
│   │   ├── transforms/
│   │   └── synthetic_generator.py
│   ├── evaluation/                               # Eval framework (DR-056)
│   │   ├── golden_set/                           # Curated eval pairs (git-lfs)
│   │   ├── metrics/                              # FID, CLIP, ArcFace, etc.
│   │   ├── bias_dashboard.py                     # DR-057 bias monitoring
│   │   └── run_eval.py
│   ├── lora_adapters/                            # Trained LoRA weights (git-lfs)
│   │   ├── base/
│   │   ├── retailers/                            # Per-retailer subdirs
│   │   └── categories/
│   ├── configs/                                  # Hydra configs
│   │   ├── inference/
│   │   ├── training/
│   │   └── evaluation/
│   ├── notebooks/                                # Research notebooks (not production)
│   ├── pyproject.toml
│   ├── Dockerfile
│   └── README.md
│
├── sdks/                                         # Retailer-facing SDKs
│   ├── ios/                                      # Swift
│   │   ├── Sources/
│   │   │   ├── TryOnSDK/                         # Public API
│   │   │   ├── Core/                             # Internal: networking, storage
│   │   │   ├── BodyScan/                         # Scan flow
│   │   │   ├── TryOn/                            # Try-on viewer
│   │   │   ├── UI/                               # Pre-built UI components
│   │   │   └── Analytics/                        # Event tracking
│   │   ├── Tests/
│   │   ├── Example/                              # Sample app
│   │   ├── Package.swift                         # SwiftPM distribution
│   │   └── README.md
│   ├── android/                                  # Kotlin
│   │   ├── tryon-sdk/
│   │   │   ├── src/main/kotlin/com/vto/sdk/
│   │   │   ├── src/test/
│   │   │   └── build.gradle.kts
│   │   ├── sample-app/
│   │   └── README.md
│   ├── web/                                      # TypeScript
│   │   ├── src/
│   │   ├── test/
│   │   ├── package.json
│   │   ├── tsconfig.json
│   │   └── README.md
│   ├── react-native/                             # RN wrapper over native
│   │   ├── src/
│   │   ├── ios/
│   │   ├── android/
│   │   └── package.json
│   └── flutter/                                  # Dart wrapper
│       ├── lib/
│       ├── example/
│       └── pubspec.yaml
│
├── dashboard/                                    # Retailer dashboard frontend
│   ├── src/
│   │   ├── app/                                  # Next.js App Router
│   │   ├── components/                           # shadcn/ui components
│   │   ├── lib/
│   │   └── styles/
│   ├── public/
│   ├── package.json
│   ├── next.config.js
│   └── README.md
│
├── packages/                                     # Shared internal packages
│   ├── contracts/                                # OpenAPI spec + generated clients
│   │   ├── openapi.yaml
│   │   ├── generated/                            # Auto-generated: typescript, go, python
│   │   └── package.json
│   ├── types/                                    # Shared TypeScript types
│   ├── go-utils/                                 # Shared Go utilities
│   ├── py-utils/                                 # Shared Python utilities
│   ├── error-codes/                              # Canonical error code catalog
│   └── test-fixtures/                            # Shared test data
│
├── infrastructure/                               # IaC + ops
│   ├── terraform/
│   │   ├── modules/
│   │   │   ├── vpc/
│   │   │   ├── ecs/
│   │   │   ├── rds/
│   │   │   ├── elasticache/
│   │   │   ├── msk/
│   │   │   ├── s3/
│   │   │   ├── cloudfront/
│   │   │   ├── kms/
│   │   │   ├── waf/
│   │   │   └── gpu-pool/
│   │   ├── environments/
│   │   │   ├── dev/
│   │   │   ├── staging/
│   │   │   └── production/
│   │   └── README.md
│   ├── docker/
│   │   ├── docker-compose.yml                    # Full local stack
│   │   ├── docker-compose.dev.yml                # Dev overrides (hot reload)
│   │   └── docker-compose.test.yml               # Integration test stack
│   ├── kubernetes/                               # K8s manifests (for RunPod burst)
│   │   ├── base/
│   │   └── overlays/
│   └── scripts/                                  # Operational scripts
│       ├── seed-local-db.sh
│       ├── generate-sbom.sh
│       ├── rotate-secrets.sh
│       └── gpu-warm-pool-check.sh
│
├── docs/                                         # All documentation
│   ├── architecture/                             # Architecture docs (ADRs)
│   │   └── adr/                                  # Architecture Decision Records
│   ├── api/                                      # API reference (generated from OpenAPI)
│   ├── sdk/                                      # SDK integration guides
│   │   ├── ios-guide.md
│   │   ├── android-guide.md
│   │   ├── web-guide.md
│   │   └── quickstart.md
│   ├── runbooks/                                 # On-call runbooks per service
│   ├── security/                                 # SOC2 evidence, threat models
│   ├── onboarding/                               # New engineer onboarding
│   └── decision-register.md                      # The DR-001 through DR-070 register
│
├── tests/                                        # Cross-service tests
│   ├── e2e/                                      # Playwright E2E tests
│   ├── load/                                     # k6 load tests
│   ├── contract/                                 # Pact contract tests
│   └── security/                                 # ZAP, semgrep custom rules
│
├── tools/                                        # Internal tooling
│   ├── codegen/                                  # OpenAPI → client generators
│   ├── benchmark/                                # Inference benchmarking tools
│   ├── data-tools/                               # Dataset curation tools
│   └── release/                                  # Release automation
│
├── .editorconfig
├── .gitignore
├── .gitattributes                                # Git-lfs config
├── Makefile                                      # Top-level commands
├── turbo.json                                    # Turborepo config
├── package.json                                  # Workspace root
├── pnpm-workspace.yaml                           # pnpm workspace
├── CONTRIBUTING.md
├── SECURITY.md
├── LICENSE
└── README.md
```

## Why each top-level folder exists

| Folder | Purpose | Why at root |
|--------|---------|-------------|
| `apps/` | Deployable services (long-running processes) | Each is independently deployable; grouping enables shared CI |
| `ai/` | AI engine code (Python) | Different language, different lifecycle, different deployment (GPU) |
| `sdks/` | Retailer-facing SDKs | Released to public registries; versioned independently |
| `dashboard/` | Retailer dashboard | Serves dashboard.tryonsdk.com; frontend concerns |
| `packages/` | Shared internal packages | Cross-cutting code (types, contracts, error codes) |
| `infrastructure/` | IaC + ops tooling | Infra is code; lives alongside app code |
| `docs/` | All documentation | Single source of truth |
| `tests/` | Cross-service tests | E2E, load, contract — span multiple services |
| `tools/` | Internal tooling | Codegen, benchmarks, release scripts |

## What does NOT belong at root

- **No `src/` at root** — would conflict with monorepo structure
- **No `scripts/` at root** — use `infrastructure/scripts/` or `tools/`
- **No `config/` at root** — config belongs per-service or in `infrastructure/`
- **No vendor folders** — use package managers

---

# 3. Microservice Design

## 14 services

Each service spec below covers: Purpose, Responsibilities, Public API, Dependencies, Scaling strategy, Database, Technology.

---

## 3.1 API Gateway

**Purpose:** Single public entry point. Routes requests, enforces auth, rate limits, terminates TLS.

**Responsibilities:**
- TLS termination
- JWT validation (RS256, public key from auth-service)
- Rate limiting (per-IP, per-tenant, per-endpoint)
- Request routing to backend services
- Request/response logging (structured)
- CORS handling
- Gzip compression
- API version routing (`/v1/`, `/v2/`)

**Public API:**
- All `/v1/*` endpoints (proxied)
- `/health` (liveness)
- `/status` (current incidents)
- `/metrics` (Prometheus)

**Dependencies:**
- auth-service (for JWKS)
- Cloudflare WAF (upstream)
- Redis (rate limit counters)

**Scaling strategy:**
- Stateless; horizontal scale on CPU
- Behind Application Load Balancer
- Target: 50 req/s per instance; auto-scale at 70% CPU

**Database:** None (stateless)

**Technology:** Go + chi router (fast, minimal allocations). Alternative considered: Envoy, Kong. Go custom is simpler for our needs.

---

## 3.2 Auth Service

**Purpose:** Issue, validate, revoke tokens. Manage OAuth client credentials.

**Responsibilities:**
- OAuth 2.0 Client Credentials grant (server-to-server)
- Shopper token issuance (scoped JWT, 1h TTL)
- Token revocation
- JWKS endpoint (public key for JWT verification)
- API key management (CRUD, rotation)
- Per-scan biometric consent recording (DR-011, DR-027)

**Public API:**
- `POST /v1/tokens` (S2S; mint shopper token)
- `POST /v1/tokens/revoke` (S2S)
- `GET /v1/.well-known/jwks.json` (public)
- `POST /v1/api-keys` (S2S; create API key)
- `GET /v1/api-keys` (S2S; list)
- `DELETE /v1/api-keys/{id}` (S2S)
- `POST /v1/consent` (SDK; record biometric consent)

**Dependencies:**
- Postgres (tokens, API keys, consent records)
- KMS (for signing key)
- Redis (revocation list cache)

**Scaling strategy:**
- Stateless; horizontal scale
- 200 req/s per instance
- Token validation cached in Redis (5min TTL)

**Database:** Postgres (`auth` schema: `api_keys`, `consent_records`, `token_audit`)

**Technology:** Go + chi + jose (JWT library)

---

## 3.3 Body Service

**Purpose:** Body profile CRUD. Stores SMPL-X parameters and measurements.

**Responsibilities:**
- Accept body scan uploads (chunked, encrypted)
- Trigger SMPL-X fitting (async, via inference-gateway)
- Store body profile (encrypted at rest)
- Manage profile lifecycle (create, read, delete)
- Enforce 12-month expiry
- Per-shopper encryption key management

**Public API:**
- `POST /v1/body_profiles` (SDK; create — uploads scan)
- `GET /v1/body_profiles/{id}` (SDK; metadata only, not raw data)
- `DELETE /v1/body_profiles/{id}` (SDK; shopper-initiated)
- `POST /v1/body_profiles/{id}/consent` (SDK)
- `GET /v1/body_profiles/{id}/consent` (SDK)

**Dependencies:**
- Postgres (profile metadata)
- S3 (encrypted SMPL-X blob storage)
- KMS (per-shopper encryption keys)
- inference-gateway (SMPL-X fitting job)
- Redis (profile cache)

**Scaling strategy:**
- Stateless; horizontal scale
- 100 req/s per instance
- Background worker for expiry enforcement

**Database:** Postgres (`body` schema: `body_profiles`, `body_measurements`). S3 for SMPL-X blobs.

**Technology:** Go + chi + pgx + aws-sdk-go-v2

---

## 3.4 Garment Service

**Purpose:** Catalog CRUD. Tracks digitization status. Stores garment representations.

**Responsibilities:**
- Accept SKU pushes from retailers (batch + single)
- Track digitization status (`pending`, `processing`, `ready`, `failed`)
- Store digitized garment representation (front image, mask, attributes)
- Trigger digitization pipeline (async)
- Handle re-digitization requests
- Webhook fire on digitization complete/failed

**Public API:**
- `POST /v1/catalog/skus` (S2S)
- `GET /v1/catalog/skus` (S2S; paginated)
- `GET /v1/catalog/skus/{sku}` (S2S or SDK)
- `POST /v1/catalog/skus/{sku}/redigitize` (S2S)
- `DELETE /v1/catalog/skus/{sku}` (S2S)
- `POST /v1/catalog/batch` (S2S; async)
- `GET /v1/catalog/batch/{job_id}` (S2S)

**Dependencies:**
- Postgres (catalog)
- S3 / R2 (garment images)
- Redis (catalog cache)
- inference-gateway (digitization jobs)
- webhook-service (events)

**Scaling strategy:**
- Stateless; horizontal scale
- 500 req/s per instance (read-heavy)
- Cache layer critical (90%+ cache hit target)

**Database:** Postgres (`catalog` schema: `skus`, `garment_representations`, `digitization_jobs`)

**Technology:** Go + chi + pgx

---

## 3.5 Try-On Service

**Purpose:** Try-on job orchestration. The main product flow.

**Responsibilities:**
- Accept try-on requests (SDK)
- Validate (shopper token, body profile exists, garment digitized)
- Submit job to inference-gateway
- Track job status (`pending`, `processing`, `succeeded`, `failed`)
- Cache results (24h TTL, DR-032)
- Generate signed CDN URLs for images
- Fire webhooks on status change
- Track billing events (`tryon_viewed` = billing trigger)

**Public API:**
- `POST /v1/tryons` (SDK)
- `GET /v1/tryons/{id}` (SDK; poll status)
- `GET /v1/tryons/{id}/image` (SDK; redirect to signed CDN URL)
- `POST /v1/tryons/{id}/views` (SDK; request additional view)

**Dependencies:**
- Postgres (try-on records)
- Redis (result cache, dedup)
- inference-gateway (job submission)
- S3 / R2 + CloudFront (image storage + CDN)
- webhook-service
- analytics-service (event emission)
- billing-service (billing events)

**Scaling strategy:**
- Stateless; horizontal scale
- 200 req/s per instance
- Polling pattern → consider WebSocket for premium tier

**Database:** Postgres (`tryon` schema: `tryons`, `tryon_views`). Redis for cache.

**Technology:** Go + chi + pgx + redis-go

---

## 3.6 Inference Gateway

**Purpose:** GPU pool manager. Submits jobs to Triton, manages warm pool, autoscaling.

**Responsibilities:**
- Maintain warm GPU pool (DR-012)
- Submit inference jobs to Triton
- Handle spot instance reclamation (checkpoint + resume)
- Autoscale GPU pool based on queue depth
- GPU utilization metrics
- Cost tracking per inference (DR-023 circuit breaker)

**Public API:** (internal only)
- `POST /internal/inference/submit` (from tryon-service, body-service, garment-service)
- `GET /internal/inference/{job_id}` (status)
- `GET /internal/inference/pool/stats` (monitoring)

**Dependencies:**
- Triton Inference Server (DR-050)
- AWS ECS / EC2 (GPU instances)
- SQS (job queue)
- Redis (job state cache)
- CloudWatch (metrics)

**Scaling strategy:**
- Control plane is stateless; data plane is GPU pool
- Scale on SQS queue depth (>5 → scale up)
- Min: 2 g5.2xlarge; Max: 16 (configurable)
- 60% on-demand + 40% spot (DR-060)

**Database:** None (state is in Redis + SQS)

**Technology:** Go + Triton client + aws-sdk-go-v2

---

## 3.7 Analytics Service

**Purpose:** Event ingestion → ClickHouse. Powers dashboards.

**Responsibilities:**
- Accept events from SDK (`POST /v1/events`)
- Batch + dedup (idempotency key, 24h TTL)
- Validate event schema
- Publish to Kafka
- Stream processor → ClickHouse
- Query API for retailer dashboards

**Public API:**
- `POST /v1/events` (SDK; single)
- `POST /v1/events/batch` (SDK; batched)
- `GET /v1/analytics/summary` (S2S)
- `GET /v1/analytics/funnel` (S2S)
- `GET /v1/analytics/top_skus` (S2S)
- `GET /v1/analytics/returns_delta` (S2S)

**Dependencies:**
- Kafka (event stream)
- ClickHouse (analytics store)
- Redis (idempotency dedup)
- Postgres (retailer metadata for joins)

**Scaling strategy:**
- Ingestion: stateless, horizontal scale (1000 req/s per instance)
- Stream processor: dedicated consumer group, parallel partitions
- ClickHouse: managed (ClickHouse Cloud), scales independently

**Database:** ClickHouse (`events` table, `daily_aggregates` materialized view)

**Technology:** Go (ingestion) + Python (stream processor with Faust or Bytewax)

---

## 3.8 Billing Service

**Purpose:** Usage metering + Stripe integration.

**Responsibilities:**
- Track billable events (`tryon_viewed`)
- Apply pricing tiers
- Generate monthly invoices (via Stripe Billing)
- Send usage alerts (50%, 80%, 100% of commit)
- Provide usage API for retailers
- Handle disputes (60-day window)

**Public API:**
- `GET /v1/billing/usage` (S2S)
- `GET /v1/billing/invoices` (S2S)
- `GET /v1/billing/invoices/{id}` (S2S)
- `GET /v1/billing/forecast` (S2S)

**Dependencies:**
- Postgres (usage records, invoices)
- Stripe Billing API
- Redis (real-time usage counters)
- Kafka (consume events for metering)
- webhook-service (threshold alerts)

**Scaling strategy:**
- Stateless; horizontal scale
- 50 req/s per instance (low volume)
- Background worker for invoice generation

**Database:** Postgres (`billing` schema: `usage_records`, `invoices`, `pricing_tiers`)

**Technology:** Go + chi + stripe-go

---

## 3.9 Webhook Service

**Purpose:** Outbound webhook delivery with retries.

**Responsibilities:**
- Subscribe to internal events (Kafka)
- Format webhook payload
- Sign with HMAC (DR-027)
- Deliver with retries (DR-041: 6 attempts over 24h)
- Track delivery history
- Disable endpoints after 6 failures
- Provide retry API for manual retries

**Public API:**
- `POST /v1/webhooks/endpoints` (S2S)
- `GET /v1/webhooks/endpoints` (S2S)
- `DELETE /v1/webhooks/endpoints/{id}` (S2S)
- `POST /v1/webhooks/endpoints/{id}/test` (S2S)
- `GET /v1/webhooks/deliveries` (S2S; paginated)
- `POST /v1/webhooks/deliveries/{id}/retry` (S2S)

**Dependencies:**
- Postgres (endpoints, deliveries)
- Kafka (event subscription)
- Redis (delivery lock — prevent duplicate concurrent deliveries)

**Scaling strategy:**
- Stateless workers; horizontal scale
- 100 concurrent deliveries per instance
- Backpressure via Kafka consumer lag

**Database:** Postgres (`webhooks` schema: `endpoints`, `deliveries`)

**Technology:** Go + chi + kafka-go

---

## 3.10 Notification Service

**Purpose:** Email + dashboard alerts.

**Responsibilities:**
- Send transactional emails (welcome, billing, alerts)
- Send dashboard in-app notifications
- Send Slack alerts (internal team)
- Templated emails (Handlebars)
- Email provider: Resend or Postmark

**Public API:** (internal only)
- `POST /internal/notifications/email`
- `POST /internal/notifications/dashboard`
- `POST /internal/notifications/slack`

**Dependencies:**
- Postgres (notification log)
- Resend API (email)
- Slack webhook (internal alerts)
- Kafka (event subscription)

**Scaling strategy:** Stateless; horizontal scale; 50 req/s per instance.

**Database:** Postgres (`notifications` schema: `notification_log`)

**Technology:** Go + chi + Resend Go SDK

---

## 3.11 Admin Service

**Purpose:** Internal admin API. Used by internal team for support, ops, debugging.

**Responsibilities:**
- Tenant management (create, suspend, delete)
- Internal user management
- Force-trigger digitization, fine-tuning
- Customer support views (no PII access)
- Audit log access
- Feature flag management

**Public API:** (internal only, behind VPN + SSO)
- `/internal/admin/tenants/*`
- `/internal/admin/users/*`
- `/internal/admin/audit/*`
- `/internal/admin/feature-flags/*`

**Dependencies:**
- Postgres (admin tables)
- Auth0 (internal SSO)
- All other services (via internal APIs)

**Scaling strategy:** Single instance is fine; internal traffic only.

**Database:** Postgres (`admin` schema)

**Technology:** Go + chi

---

## 3.12 Dashboard API (BFF)

**Purpose:** Backend-for-Frontend for retailer dashboard.

**Responsibilities:**
- Aggregate data from analytics, billing, catalog services
- Format for dashboard UI
- Handle SSO (SAML 2.0 for enterprise retailers)
- RBAC (admin, developer, billing, read-only — DR-014)
- WebSocket for real-time updates

**Public API:**
- `/dashboard/auth/sso/callback`
- `/dashboard/overview`
- `/dashboard/catalog/*`
- `/dashboard/analytics/*`
- `/dashboard/billing/*`
- `/dashboard/settings/*`
- `/dashboard/developers/*` (API keys, webhooks, logs)
- `/dashboard/ws` (WebSocket)

**Dependencies:**
- All other services (aggregator pattern)
- Auth0 (SSO)
- Redis (session cache)

**Scaling strategy:** Stateless; horizontal scale; 100 req/s per instance.

**Database:** Postgres (`dashboard` schema: `dashboard_users`, `dashboard_sessions`)

**Technology:** Node.js + TypeScript + Fastify + ws (WebSocket)

---

## 3.13 Dataset Service (AI-adjacent)

**Purpose:** Manage training datasets. Track data lineage. Version datasets.

**Responsibilities:**
- Ingest production try-on pairs (with consent)
- Track dataset versions (DVC integration)
- Provide dataset registry for training jobs
- Manage consented shopper data
- Data retention enforcement

**Public API:** (internal only)
- `/internal/datasets/*`

**Dependencies:**
- S3 (dataset storage)
- Postgres (dataset metadata, lineage)
- DVC (versioning)

**Scaling strategy:** Low traffic; single instance.

**Database:** Postgres (`dataset` schema)

**Technology:** Python + FastAPI

---

## 3.14 Training Service (AI-adjacent)

**Purpose:** Manage fine-tuning jobs. Per-retailer LoRA, base fine-tunes.

**Responsibilities:**
- Submit fine-tune jobs to GPU cluster
- Track job status
- Manage LoRA adapter storage
- Trigger evaluation after fine-tune
- Promote adapters to production (after eval passes)

**Public API:** (internal only)
- `/internal/training/jobs`
- `/internal/training/jobs/{id}`
- `/internal/training/adapters/*`

**Dependencies:**
- ECS / EKS (training jobs on A100)
- S3 (adapter storage)
- Postgres (job metadata)
- evaluation-service (post-train)

**Scaling strategy:** Control plane only; data plane is GPU cluster.

**Database:** Postgres (`training` schema)

**Technology:** Python + FastAPI

---

## 3.15 Evaluation Service (AI-adjacent)

**Purpose:** Run model evaluations. Gate deployments.

**Responsibilities:**
- Run golden eval set (DR-056)
- Compute bias metrics (DR-057)
- Run production canary (1% traffic)
- Auto-rollback if quality degrades
- Track model version quality over time

**Public API:** (internal only)
- `/internal/eval/run`
- `/internal/eval/results/{run_id}`
- `/internal/eval/bias-dashboard`

**Dependencies:**
- S3 (golden set, eval results)
- Postgres (eval metadata)
- inference-gateway (to run new model)

**Scaling strategy:** On-demand; triggered by training service.

**Database:** Postgres (`evaluation` schema)

**Technology:** Python + FastAPI

---

## 3.16 Monitoring Service

**Purpose:** Observability aggregation. NOT Prometheus/Loki (we use managed), but the glue.

**Responsibilities:**
- Custom business metrics (try-ons/min, GPU utilization, cost/try-on)
- SLO tracking
- Alert routing (PagerDuty)
- Status page publishing

**Public API:** (internal only)
- `/internal/monitoring/slos`
- `/internal/monitoring/incidents`

**Dependencies:**
- Datadog (metrics)
- Sentry (errors)
- PagerDuty (alerts)
- Statuspage (public status)

**Scaling strategy:** Minimal; mostly a forwarder.

**Technology:** Go + chi

---

## Service interaction diagram

```
                     ┌─────────────────────┐
                     │   Cloudflare WAF    │
                     └──────────┬──────────┘
                                │
                     ┌──────────▼──────────┐
                     │    API Gateway      │
                     └────┬─────────┬──────┘
                          │         │
              ┌───────────┘         └───────────┐
              │                                 │
       ┌──────▼──────┐                   ┌──────▼──────┐
       │ Auth Svc    │                   │ Dashboard   │
       └──────┬──────┘                   │ API (BFF)   │
              │                          └──────┬──────┘
              │                                 │
       ┌──────▼─────────────────────────────────▼──────┐
       │           Body / Garment / TryOn /            │
       │           Analytics / Billing                 │
       │           (business services)                 │
       └──────┬───────────────────────────────────────┘
              │
       ┌──────▼──────┐
       │ Inference   │
       │ Gateway     │
       └──────┬──────┘
              │
       ┌──────▼──────┐
       │ Triton Pool │ (GPU instances)
       └─────────────┘

   Async events flow via Kafka:
   ┌──────────────────────────────────────────────────┐
   │ Kafka: events, webhooks, billing, training       │
   └──────────────────────────────────────────────────┘
              │
       ┌──────▼──────┐  ┌─────────────┐  ┌────────────┐
       │ Webhook Svc │  │ Analytics   │  │ Billing    │
       │             │  │ Stream Proc │  │ Meter      │
       └─────────────┘  └─────────────┘  └────────────┘
```

---

# 4. Database Design

## Database topology

| Database | Engine | Purpose |
|----------|--------|---------|
| Primary OLTP | PostgreSQL 16 (Aurora) | Transactional data |
| Cache | Redis 7 (ElastiCache) | Caching, rate limits, dedup |
| Object storage | S3 + Cloudflare R2 | Images, SMPL-X blobs, datasets |
| Analytics | ClickHouse Cloud | Event analytics |
| Message queue | Amazon MSK (Kafka) | Event streaming |
| Job queue | Amazon SQS | Inference job queue |
| Vector DB | pgvector (in Postgres) | Garment attribute embeddings |

## 4.1 PostgreSQL schemas

One database, multiple schemas. Schema-per-tenant is at the application layer (DR-008) — we isolate via `retailer_id` foreign keys with strict RLS.

### `auth` schema

```sql
CREATE SCHEMA auth;

CREATE TABLE auth.api_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    retailer_id UUID NOT NULL REFERENCES retailers(id),
    name VARCHAR(100) NOT NULL,
    key_hash VARCHAR(128) NOT NULL,  -- SHA-256 hash; raw key never stored
    key_prefix VARCHAR(10) NOT NULL, -- first 8 chars for identification
    scopes TEXT[] NOT NULL DEFAULT '{"server_to_server"}',
    last_used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID NOT NULL REFERENCES dashboard_users(id),
    revoked_at TIMESTAMPTZ,
    revoked_reason TEXT
);
CREATE INDEX idx_api_keys_key_hash ON auth.api_keys(key_hash) WHERE revoked_at IS NULL;
CREATE INDEX idx_api_keys_retailer ON auth.api_keys(retailer_id) WHERE revoked_at IS NULL;

CREATE TABLE auth.consent_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    retailer_id UUID NOT NULL REFERENCES retailers(id),
    shopper_ref VARCHAR(200) NOT NULL,  -- opaque retailer-issued ID
    consent_type VARCHAR(50) NOT NULL,  -- 'body_scan', 'training_use'
    consent_version VARCHAR(20) NOT NULL, -- '1.0', '1.1', etc.
    consented_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at TIMESTAMPTZ,
    ip_address INET,
    user_agent TEXT,
    signature TEXT NOT NULL  -- HMAC of consent payload
);
CREATE INDEX idx_consent_retailer_shopper ON auth.consent_records(retailer_id, shopper_ref);

CREATE TABLE auth.token_audit (
    id BIGSERIAL PRIMARY KEY,
    token_id VARCHAR(100) NOT NULL,
    retailer_id UUID NOT NULL,
    shopper_ref VARCHAR(200),
    issued_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    scopes TEXT[]
);
CREATE INDEX idx_token_audit_token ON auth.token_audit(token_id);
```

### `body` schema

```sql
CREATE SCHEMA body;

CREATE TABLE body.body_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    retailer_id UUID NOT NULL REFERENCES retailers(id),
    shopper_ref VARCHAR(200) NOT NULL,
    smplx_blob_key VARCHAR(500) NOT NULL,  -- S3 key
    smplx_blob_kms_key_id VARCHAR(200) NOT NULL,
    measurements JSONB NOT NULL,  -- {chest_cm, waist_cm, hip_cm, inseam_cm, height_cm}
    scan_device VARCHAR(100),  -- 'iphone_pro_lidar', 'android_arcore', 'rgb_2photo'
    scan_quality_score FLOAT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,  -- created_at + 12 months (DR-011)
    deleted_at TIMESTAMPTZ,
    UNIQUE(retailer_id, shopper_ref) WHERE deleted_at IS NULL
);
CREATE INDEX idx_body_profiles_retailer_shopper ON body.body_profiles(retailer_id, shopper_ref) WHERE deleted_at IS NULL;
CREATE INDEX idx_body_profiles_expiry ON body.body_profiles(expires_at) WHERE deleted_at IS NULL;
```

### `catalog` schema

```sql
CREATE SCHEMA catalog;

CREATE TYPE digitization_status AS ENUM ('pending', 'processing', 'ready', 'failed', 'manual_qc');

CREATE TABLE catalog.skus (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    retailer_id UUID NOT NULL REFERENCES retailers(id),
    sku VARCHAR(200) NOT NULL,
    name VARCHAR(500),
    category VARCHAR(100),
    metadata JSONB,  -- retailer-provided
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    UNIQUE(retailer_id, sku) WHERE deleted_at IS NULL
);
CREATE INDEX idx_skus_retailer_sku ON catalog.skus(retailer_id, sku);
CREATE INDEX idx_skus_category ON catalog.skus(retailer_id, category);

CREATE TABLE catalog.garment_representations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sku_id UUID NOT NULL REFERENCES catalog.skus(id),
    front_image_url VARCHAR(1000),
    back_image_url VARCHAR(1000),
    segmentation_mask_url VARCHAR(1000),
    attributes JSONB,  -- {neckline, sleeve, length, fabric_category, pattern}
    texture_embedding FLOAT[],  -- 512-dim
    quality_score FLOAT,
    digitization_status digitization_status NOT NULL DEFAULT 'pending',
    digitization_version VARCHAR(50),  -- pipeline version
    digitized_at TIMESTAMPTZ,
    failure_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_garment_rep_sku ON catalog.garment_representations(sku_id);
CREATE INDEX idx_garment_rep_status ON catalog.garment_representations(digitization_status);

-- pgvector index for similar-garment search (Phase 2)
CREATE INDEX idx_garment_texture_embedding ON catalog.garment_representations
    USING ivfflat (texture_embedding vector_cosine_ops) WITH (lists = 100);
```

### `tryon` schema

```sql
CREATE SCHEMA tryon;

CREATE TYPE tryon_status AS ENUM ('pending', 'processing', 'succeeded', 'failed', 'expired');

CREATE TABLE tryon.tryons (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    retailer_id UUID NOT NULL REFERENCES retailers(id),
    shopper_ref VARCHAR(200) NOT NULL,
    body_profile_id UUID NOT NULL REFERENCES body.body_profiles(id),
    sku_id UUID NOT NULL REFERENCES catalog.skus(id),
    garment_sku VARCHAR(200) NOT NULL,
    size VARCHAR(20),
    view VARCHAR(20) NOT NULL DEFAULT 'front',
    status tryon_status NOT NULL DEFAULT 'pending',
    image_url VARCHAR(1000),
    image_expires_at TIMESTAMPTZ,
    quality_score FLOAT,
    model_version VARCHAR(50),
    render_time_ms INTEGER,
    error_code VARCHAR(50),
    error_detail TEXT,
    cache_key VARCHAR(200),  -- for dedup (DR-032)
    billed BOOLEAN NOT NULL DEFAULT FALSE,
    billed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);
CREATE INDEX idx_tryons_retailer ON tryon.tryons(retailer_id, created_at DESC);
CREATE INDEX idx_tryons_cache_key ON tryon.tryons(cache_key) WHERE status = 'succeeded';
CREATE INDEX idx_tryons_status ON tryon.tryons(status) WHERE status IN ('pending', 'processing');
CREATE INDEX idx_tryons_shopper ON tryon.tryons(retailer_id, shopper_ref, created_at DESC);

-- Partition by month for high-volume table
CREATE TABLE tryon.tryons_2026_07 PARTITION OF tryon.tryons
    FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
-- ... continue monthly partitions
```

### `billing` schema

```sql
CREATE SCHEMA billing;

CREATE TABLE billing.pricing_tiers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    retailer_id UUID REFERENCES retailers(id),  -- NULL = default tier
    name VARCHAR(100) NOT NULL,
    min_volume INTEGER NOT NULL DEFAULT 0,
    max_volume INTEGER,
    price_per_tryon_cents INTEGER NOT NULL,
    minimum_monthly_commit_cents INTEGER NOT NULL DEFAULT 0,
    effective_from TIMESTAMPTZ NOT NULL,
    effective_to TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE billing.usage_records (
    id BIGSERIAL PRIMARY KEY,
    retailer_id UUID NOT NULL REFERENCES retailers(id),
    tryon_id UUID NOT NULL REFERENCES tryon.tryons(id),
    event_type VARCHAR(50) NOT NULL,  -- 'tryon_viewed'
    billed_amount_cents INTEGER NOT NULL,
    pricing_tier_id UUID NOT NULL REFERENCES billing.pricing_tiers(id),
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    invoice_id UUID  -- NULL until invoiced
);
CREATE INDEX idx_usage_retailer_date ON billing.usage_records(retailer_id, recorded_at DESC);
CREATE INDEX idx_usage_invoice ON billing.usage_records(invoice_id) WHERE invoice_id IS NOT NULL;

CREATE TABLE billing.invoices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    retailer_id UUID NOT NULL REFERENCES retailers(id),
    stripe_invoice_id VARCHAR(100) UNIQUE,
    period_start TIMESTAMPTZ NOT NULL,
    period_end TIMESTAMPTZ NOT NULL,
    subtotal_cents INTEGER NOT NULL,
    tax_cents INTEGER NOT NULL DEFAULT 0,
    total_cents INTEGER NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'open',  -- 'open', 'paid', 'void', 'uncollectible'
    due_date TIMESTAMPTZ NOT NULL,
    paid_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_invoices_retailer ON billing.invoices(retailer_id, period_start DESC);
```

### `webhooks` schema

```sql
CREATE SCHEMA webhooks;

CREATE TABLE webhooks.endpoints (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    retailer_id UUID NOT NULL REFERENCES retailers(id),
    url VARCHAR(1000) NOT NULL,
    secret_hash VARCHAR(128) NOT NULL,  -- bcrypt hash of signing secret
    events TEXT[] NOT NULL,  -- subscribed events
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    disabled_at TIMESTAMPTZ,
    disabled_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_webhook_endpoints_retailer ON webhooks.endpoints(retailer_id) WHERE is_active = TRUE;
CREATE INDEX idx_webhook_endpoints_events ON webhooks.endpoints USING GIN (events);

CREATE TABLE webhooks.deliveries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    endpoint_id UUID NOT NULL REFERENCES webhooks.endpoints(id),
    event_type VARCHAR(100) NOT NULL,
    payload JSONB NOT NULL,
    signature VARCHAR(200) NOT NULL,
    attempt_number INTEGER NOT NULL DEFAULT 1,
    status VARCHAR(20) NOT NULL,  -- 'pending', 'delivered', 'failed', 'disabled'
    response_code INTEGER,
    response_body TEXT,
    next_retry_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_webhook_deliveries_pending ON webhooks.deliveries(next_retry_at) WHERE status = 'pending';
CREATE INDEX idx_webhook_deliveries_endpoint ON webhooks.deliveries(endpoint_id, created_at DESC);
```

### `analytics` schema (in ClickHouse, but mirrored)

ClickHouse doesn't use schemas the same way. Tables:

```sql
-- ClickHouse
CREATE TABLE analytics.events (
    event_id String,
    event_type String,
    retailer_id String,
    shopper_token_id String,
    session_id String,
    tryon_id String,
    garment_sku String,
    body_profile_id String,
    device_platform String,
    device_os_version String,
    app_version String,
    locale String,
    timestamp DateTime64(3),
    custom_attributes String  -- JSON
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (retailer_id, timestamp)
TTL timestamp + INTERVAL 13 MONTH;

CREATE MATERIALIZED VIEW analytics.daily_aggregates
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(date)
ORDER BY (retailer_id, date, event_type)
AS
SELECT
    retailer_id,
    toDate(timestamp) AS date,
    event_type,
    count() AS event_count
FROM analytics.events
GROUP BY retailer_id, date, event_type;
```

### `dashboard` schema

```sql
CREATE SCHEMA dashboard;

CREATE TABLE dashboard.dashboard_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    retailer_id UUID NOT NULL REFERENCES retailers(id),
    email VARCHAR(500) NOT NULL,
    name VARCHAR(500),
    role VARCHAR(50) NOT NULL,  -- 'admin', 'developer', 'billing', 'read_only'
    auth0_user_id VARCHAR(200) UNIQUE,
    last_login_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(retailer_id, email)
);

CREATE TABLE dashboard.dashboard_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES dashboard.dashboard_users(id),
    token_hash VARCHAR(128) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### `retailers` (top-level; shared)

```sql
CREATE SCHEMA public;

CREATE TABLE retailers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(500) NOT NULL,
    legal_name VARCHAR(500),
    billing_email VARCHAR(500),
    technical_contact_email VARCHAR(500),
    status VARCHAR(50) NOT NULL DEFAULT 'active',  -- 'active', 'suspended', 'churned'
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    settings JSONB NOT NULL DEFAULT '{}'
);

CREATE TABLE retailer_features (
    retailer_id UUID PRIMARY KEY REFERENCES retailers(id),
    features JSONB NOT NULL DEFAULT '{}',  -- feature flags
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

## 4.2 Redis key schema

```
# Rate limiting
ratelimit:{retailer_id}:{endpoint}    → counter (TTL: 60s)
ratelimit:{ip}:global                  → counter (TTL: 60s)

# Auth
jwks:current                           → JSON (TTL: 5min)
token:revoked:{token_id}               → 1 (TTL: remaining token TTL)

# Body profiles
body_profile:{profile_id}              → JSON (TTL: 10min)

# Catalog
catalog:sku:{retailer_id}:{sku}        → JSON (TTL: 5min)
catalog:digitized:{retailer_id}        → SET of SKUs (TTL: 1h)

# Try-on cache
tryon:cache:{cache_key}                → JSON {tryon_id, image_url} (TTL: 24h)
tryon:dedup:{tryon_id}                 → 1 (TTL: 24h, prevents double-billing)

# Inference
inference:job:{job_id}                 → JSON (TTL: 1h)
inference:pool:warm_count              → counter

# Billing
billing:usage:{retailer_id}:current_month → counter (TTL: end of month)

# Webhooks
webhook:delivery_lock:{delivery_id}    → 1 (TTL: 30s, prevents concurrent delivery)

# Dashboard
dashboard:session:{session_id}         → JSON (TTL: 24h)
```

## 4.3 S3 / R2 bucket layout

```
vto-prod-body-profiles/                  # Per-region bucket
  └── {retailer_id}/{profile_id}.enc     # Encrypted SMPL-X blob

vto-prod-garment-images/
  └── {retailer_id}/{sku}/
      ├── front.webp
      ├── back.webp
      └── mask.png

vto-prod-tryon-images/
  └── {retailer_id}/{yyyymm}/{tryon_id}.webp

vto-prod-catalog-uploads/                # Retailer original photos
  └── {retailer_id}/{upload_batch_id}/

vto-prod-datasets/                       # Training datasets
  ├── golden_eval/
  ├── production_pairs/
  └── synthetic/

vto-prod-lora-adapters/
  ├── base/
  ├── retailers/{retailer_id}/
  └── categories/{category}/

vto-cold-archive/                        # S3 Glacier
  └── expired_body_profiles/
```

## 4.4 Indexing strategy

- All foreign keys have indexes
- All `WHERE` clause columns in queries have indexes
- Partial indexes (e.g., `WHERE deleted_at IS NULL`) for soft-deleted tables
- Composite indexes for common query patterns
- Partition `tryon.tryons` by month (high-volume)
- Use `pgvector` for garment similarity (Phase 2)

---

# 5. API Specification

## OpenAPI 3.1 spec (abridged; full at `packages/contracts/openapi.yaml`)

### Common headers

```
Authorization: Bearer {token}
Content-Type: application/json
Accept: application/json
X-Request-Id: {uuid}     # Client-generated for tracing
Idempotency-Key: {uuid}  # For POST endpoints
```

### Error response (RFC 7807)

```json
{
  "type": "https://docs.tryonsdk.com/errors/{code}",
  "title": "Try-on generation failed",
  "status": 422,
  "detail": "Garment SKU has not been digitized yet.",
  "instance": "req_abc123",
  "errors": [
    {
      "code": "garment_not_digitized",
      "field": "garment_sku",
      "value": "SKU-12345"
    }
  ]
}
```

## 5.1 Authentication endpoints

### POST /v1/tokens
Mint a scoped shopper token. Server-to-server.

**Request:**
```json
{
  "shopper_id": "retailer_user_12345",
  "scopes": ["body_scan", "tryon", "events"],
  "ttl_seconds": 3600
}
```

**Response (200):**
```json
{
  "data": {
    "access_token": "eyJhbGciOi...",
    "token_type": "Bearer",
    "expires_in": 3600,
    "shopper_token_id": "st_abc123"
  },
  "meta": { "request_id": "req_abc123" }
}
```

**Errors:** 401 (invalid server token), 403 (scopes not allowed), 422 (validation)

### POST /v1/tokens/revoke
```json
{ "shopper_token_id": "st_abc123" }
```
**Response:** 204 No Content

### GET /v1/.well-known/jwks.json
Public endpoint. Returns JWKS for JWT verification.
```json
{
  "keys": [
    { "kty": "RSA", "kid": "key-1", "use": "sig", "alg": "RS256", "n": "...", "e": "AQAB" }
  ]
}
```

## 5.2 Body endpoints

### POST /v1/body_profiles
Create body profile. SDK only.

**Headers:**
```
Authorization: Bearer {shopper_token}
Content-Type: multipart/form-data
```

**Body (multipart):**
- `scan_data`: binary (encrypted mesh file)
- `metadata`: JSON (`{scan_device, scan_quality_score, measurements}`)
- `consent_receipt`: JSON (`{consent_version, consented_at, signature}`)

**Response (201):**
```json
{
  "data": {
    "id": "bp_xyz789",
    "status": "processing",
    "estimated_ready_seconds": 5,
    "poll_url": "/v1/body_profiles/bp_xyz789"
  }
}
```

### GET /v1/body_profiles/{id}
```json
{
  "data": {
    "id": "bp_xyz789",
    "status": "ready",
    "measurements": {
      "chest_cm": 96.2,
      "waist_cm": 78.5,
      "hip_cm": 102.1,
      "inseam_cm": 81.0,
      "height_cm": 175.0
    },
    "scan_device": "iphone_pro_lidar",
    "quality_score": 0.92,
    "created_at": "2026-07-10T12:00:00Z",
    "expires_at": "2027-07-10T12:00:00Z"
  }
}
```

### DELETE /v1/body_profiles/{id}
**Response:** 204 No Content (deletion processed within 72h SLA per DR-011)

## 5.3 Garment endpoints

### POST /v1/catalog/skus
Push single SKU. Server-to-server.

**Request:**
```json
{
  "sku": "RETAILER_SKU_12345",
  "name": "Silk Wrap Dress",
  "category": "dress",
  "gender": "women",
  "color": "emerald",
  "fabric": "silk",
  "image_urls": [
    "https://cdn.retailer.com/products/12345/front.jpg",
    "https://cdn.retailer.com/products/12345/back.jpg"
  ],
  "size_chart": {
    "XS": { "chest_cm": 84, "waist_cm": 66 },
    "S": { "chest_cm": 88, "waist_cm": 70 }
  },
  "metadata": {}
}
```

**Response (201):**
```json
{
  "data": {
    "sku": "RETAILER_SKU_12345",
    "digitization_status": "pending",
    "estimated_ready_hours": 24
  }
}
```

### POST /v1/catalog/batch
Bulk push. Returns job_id.

**Request:**
```json
{
  "skus": [ { ... }, { ... } ]
}
```

**Response (202):**
```json
{
  "data": {
    "job_id": "job_batch_abc",
    "total_skus": 500,
    "status": "processing"
  }
}
```

### GET /v1/catalog/skus/{sku}
```json
{
  "data": {
    "sku": "RETAILER_SKU_12345",
    "digitization_status": "ready",
    "quality_score": 0.92,
    "digitized_at": "2026-07-09T12:00:00Z",
    "representation": {
      "front_image_url": "https://cdn.tryonsdk.com/...",
      "back_image_url": "https://cdn.tryonsdk.com/...",
      "segmentation_mask_url": "https://cdn.tryonsdk.com/...",
      "attributes": {
        "neckline": "v_neck",
        "sleeve": "sleeveless",
        "length": "knee",
        "fabric_category": "silk",
        "pattern": "solid"
      }
    }
  }
}
```

## 5.4 Try-On endpoints

### POST /v1/tryons
Request try-on generation. SDK only.

**Request:**
```json
{
  "body_profile_id": "bp_xyz789",
  "garment_sku": "RETAILER_SKU_12345",
  "size": "M",
  "view": "front"
}
```

**Response (202):**
```json
{
  "data": {
    "tryon_id": "tryon_abc123",
    "status": "pending",
    "estimated_wait_seconds": 2,
    "poll_url": "/v1/tryons/tryon_abc123"
  }
}
```

### GET /v1/tryons/{id}
```json
{
  "data": {
    "tryon_id": "tryon_abc123",
    "status": "succeeded",
    "image_url": "https://cdn.tryonsdk.com/tryons/abc123.webp",
    "image_url_expires_at": "2026-07-11T12:00:00Z",
    "thumbnail_url": "https://cdn.tryonsdk.com/tryons/abc123_thumb.webp",
    "metadata": {
      "model_version": "idm-vton-v2.3",
      "quality_score": 0.89,
      "render_time_ms": 1820
    },
    "billing": {
      "billed": false,
      "will_bill_on": "view"
    }
  }
}
```

### POST /v1/tryons/{id}/views
Request additional view (back, side).

```json
{ "view": "back" }
```

### GET /v1/tryons/{id}/image
Redirect (302) to signed CDN URL.

## 5.5 Events endpoints

### POST /v1/events
```json
{
  "event_id": "evt_uuid_001",
  "event_type": "tryon_viewed",
  "timestamp": "2026-07-10T12:34:56.789Z",
  "session_id": "sess_xyz",
  "tryon_id": "tryon_abc123",
  "device": {
    "platform": "ios",
    "os_version": "17.4.1",
    "app_version": "1.2.3"
  }
}
```
**Response:** 204 No Content

### POST /v1/events/batch
```json
{
  "events": [ { ... }, { ... } ]
}
```

## 5.6 Attribution endpoints

### POST /v1/attribution/purchase
Retailer → us. Server-to-server.

```json
{
  "tryon_id": "tryon_abc123",
  "order_id": "retailer_order_67890",
  "order_total_cents": 12500,
  "purchased_sku": "RETAILER_SKU_12345",
  "purchased_size": "M",
  "purchased_at": "2026-07-10T13:00:00Z"
}
```

### POST /v1/attribution/return
```json
{
  "tryon_id": "tryon_abc123",
  "order_id": "retailer_order_67890",
  "returned_at": "2026-07-15T10:00:00Z",
  "return_reason": "fit_issue"
}
```

## 5.7 Analytics endpoints

### GET /v1/analytics/summary?from=2026-07-01&to=2026-07-10
```json
{
  "data": {
    "period": { "from": "2026-07-01", "to": "2026-07-10" },
    "metrics": {
      "tryons_generated": 12847,
      "tryons_viewed": 11203,
      "scan_completions": 3201,
      "billed_amount_cents": 1680450,
      "tryon_to_cart_rate": 0.18,
      "tryon_to_purchase_rate": 0.08,
      "return_rate_tryon": 0.12,
      "return_rate_non_tryon": 0.22
    }
  }
}
```

### GET /v1/analytics/funnel
### GET /v1/analytics/top_skus
### GET /v1/analytics/returns_delta

## 5.8 Billing endpoints

### GET /v1/billing/usage
```json
{
  "data": {
    "period": "2026-07",
    "tryons_viewed": 12847,
    "tier": { "name": "Volume 1", "price_per_tryon_cents": 12 },
    "current_usage_cents": 154164,
    "minimum_commit_cents": 200000,
    "forecasted_total_cents": 480000
  }
}
```

### GET /v1/billing/invoices
### GET /v1/billing/invoices/{id} → PDF
### GET /v1/billing/forecast

## 5.9 Webhook endpoints

### POST /v1/webhooks/endpoints
```json
{
  "url": "https://api.retailer.com/vto-webhooks",
  "events": ["tryon.succeeded", "tryon.viewed", "billing.threshold_reached"]
}
```

**Response (201):**
```json
{
  "data": {
    "id": "wh_ep_abc",
    "url": "https://api.retailer.com/vto-webhooks",
    "events": ["tryon.succeeded", "tryon.viewed", "billing.threshold_reached"],
    "secret": "whsec_xxx_reveal_once",  // shown once
    "is_active": true,
    "created_at": "2026-07-10T12:00:00Z"
  }
}
```

### Webhook payload (outbound)
```json
{
  "event_id": "evt_xyz",
  "event_type": "tryon.viewed",
  "timestamp": "2026-07-10T12:34:56Z",
  "data": {
    "tryon_id": "tryon_abc123",
    "retailer_id": "ret_123",
    "shopper_token_id": "st_abc",
    "garment_sku": "RETAILER_SKU_12345",
    "billed_amount_cents": 15
  }
}
```

**Headers:**
```
TryOnSDK-Signature: t=1690000000,v1=abc123def456...
TryOnSDK-Event: tryon.viewed
TryOnSDK-Delivery: whdel_uuid
Content-Type: application/json
```

## 5.10 Health endpoints

### GET /v1/health
```json
{ "status": "ok", "version": "1.0.0", "timestamp": "2026-07-10T12:00:00Z" }
```

### GET /v1/status
Returns current incidents from Statuspage API.

---

# 6. SDK Design

## 6.1 iOS SDK (Swift)

### Public API

```swift
public enum TryOnSDK {
    public static func configure(_ config: Configuration)
    public static var shared: TryOnSDKInstance { get }
}

public final class TryOnSDKInstance {
    // Configuration
    public func setShopperToken(_ token: String)
    public func setTheme(_ theme: Theme)
    public func setLogLevel(_ level: LogLevel)
    public func setEnvironment(_ env: Environment)

    // Body profile
    public func hasBodyProfile(completion: @escaping (Bool) -> Void)
    public func startBodyScan(
        in presenter: UIViewController,
        theme: Theme? = nil,
        completion: @escaping (Result<String, TryOnError>) -> Void
    )
    public func deleteBodyProfile(completion: @escaping (Result<Void, TryOnError>) -> Void)

    // Try-on
    public func generateTryOn(
        _ request: TryOnRequest,
        completion: @escaping (Result<TryOnResult, TryOnError>) -> Void
    ) -> CancellableTask

    public func makeTryOnViewer(
        for tryonId: String,
        delegate: TryOnViewerDelegate?
    ) -> UIViewController

    // Analytics
    public func trackEvent(name: String, attributes: [String: Any])
    public func setShopperAttribute(_ key: String, value: Any?)
}

public struct Configuration {
    public let tenantId: String
    public var environment: Environment = .production
    public var logLevel: LogLevel = .error
    public var enableTelemetry: Bool = true
    public var fallbackToProductImages: Bool = true
}

public struct Theme {
    public var primaryColor: UIColor
    public var cornerRadius: CGFloat
    public var fontFamily: String?
    public var backgroundColor: UIColor
}

public struct TryOnRequest {
    public let garmentSKU: String
    public var size: Size = .recommended
    public var view: View = .front
}

public enum Size {
    case recommended
    case explicit(String)
}

public enum View: String {
    case front, back, side
}

public struct TryOnResult {
    public let tryonId: String
    public let imageUrl: URL
    public let thumbnailUrl: URL
    public let expiresAt: Date
    public let qualityScore: Float
}

public enum TryOnError: Error {
    case networkError(underlying: Error)
    case rateLimited(retryAfter: TimeInterval)
    case serverError(requestId: String)
    case authenticationFailed
    case consentRevoked
    case garmentNotDigitized(sku: String)
    case bodyProfileExpired
    case quotaExceeded
    case validationError(field: String, message: String)
    case unknown(requestId: String)
}

public protocol CancellableTask: AnyObject {
    func cancel()
}
```

### Threading
- All public methods are thread-safe
- Completion handlers called on main queue
- Internal work on background queues

### Caching
- Body profile ID cached in Keychain
- Last 20 try-on results cached in CoreData (24h TTL)
- Catalog status cached for 5 min

### Retry strategy
- Network errors: exponential backoff (1, 2, 4, 8, 16s), max 5 retries
- Server errors: same
- Rate limits: honor `Retry-After`
- All retries respect `Idempotency-Key`

### Offline support
- Try-on requests queued locally (max 10, encrypted)
- Events always queued locally
- Cached try-on results viewable offline (24h)

## 6.2 Android SDK (Kotlin)

Mirror of iOS API. Suspending functions instead of completion handlers.

```kotlin
class TryOnSDK private constructor() {
    companion object {
        fun configure(context: Context, config: Configuration)
        val instance: TryOnSDK
    }

    suspend fun setShopperToken(token: String)
    suspend fun hasBodyProfile(): Boolean
    suspend fun startBodyScan(
        activity: Activity,
        theme: Theme? = null
    ): BodyScanResult  // Sealed class: Success(profileId), Cancelled, Error

    suspend fun deleteBodyProfile()
    suspend fun generateTryOn(request: TryOnRequest): TryOnResult
    fun makeTryOnViewerIntent(tryonId: String, context: Context): Intent

    fun trackEvent(name: String, attributes: Map<String, Any>)
    fun setShopperAttribute(key: String, value: Any?)
}
```

## 6.3 Web SDK (TypeScript)

```typescript
export class TryOnSDK {
  static async configure(config: Configuration): Promise<TryOnSDK>
  async setShopperToken(token: string): Promise<void>
  async hasBodyProfile(): Promise<boolean>
  async startBodyScan(options?: { theme?: Theme }): Promise<BodyProfile>
  async deleteBodyProfile(): Promise<void>
  async generateTryOn(request: TryOnRequest): Promise<TryOnResult>
  renderTryOnViewer(options: {
    container: HTMLElement
    tryonId: string
    onEvent?: (event: TryOnEvent) => void
  }): TryOnViewerHandle
  trackEvent(name: string, attributes?: Record<string, unknown>): void
  setShopperAttribute(key: string, value: unknown): void
}

export interface Configuration {
  tenantId: string
  environment?: 'sandbox' | 'production'
  logLevel?: 'debug' | 'info' | 'warn' | 'error'
  enableTelemetry?: boolean
}
```

## 6.4 Flutter + React Native

Thin wrappers over native SDKs via platform channels / native modules. Same API surface, translated to Dart / TypeScript idioms.

Deferred per DR-031 — built only when 3+ retailers request.

---

# 7. AI Service Design

## Project structure (already shown in Section 2; details here)

### `ai/inference/`

**`pipelines/tryon_pipeline.py`**
- `class TryOnPipeline` — orchestrates the 10-stage pipeline from AI architecture doc
- `async def run(request: TryOnRequest) -> TryOnResult`
- Loads models from Triton, manages GPU memory, handles batching

**`pipelines/digitization_pipeline.py`**
- `class DigitizationPipeline` — garment digitization (8 stages)
- `async def run(sku: SKUInput) -> DigitizedGarment`

**`pipelines/body_scan_pipeline.py`**
- `class BodyScanPipeline` — scan → SMPL-X fitting
- `async def run(scan_data: bytes) -> BodyProfile`

### `ai/inference/models/`

Each model is a Triton client wrapper:
```python
class IDMVTONModel:
    def __init__(self, triton_url: str, model_name: str, version: str)
    async def infer(self, inputs: TryOnInputs) -> TryOnOutputs
    def load_lora(self, adapter_path: str)  # Per-retailer LoRA swap

class GarmentSegmentationModel: ...
class OpenPoseModel: ...
class ArcFaceModel: ...
class DensePoseModel: ...
class DepthAnythingModel: ...
class CodeFormerModel: ...
class CLIPScorerModel: ...
```

### `ai/inference/optimizers/`

**`tensorrt_compiler.py`**
- `def compile(model: torch.nn.Module, output_path: str, fp16: bool = True)`
- Compiles PyTorch model to TensorRT engine
- Hardware-specific (must rebuild per GPU type)

**`lcm_lora.py`**
- Loads LCM-LoRA adapter onto diffusion model
- Reduces sampling from 30 steps to 4 steps

**`fp16_converter.py`**
- Converts model to FP16, with FP32 fallback for unstable layers

### `ai/training/`

**`base_finetune.py`**
- Full fine-tune of IDM-VTON
- Uses 8× A100 on AWS p4d.24xlarge
- Triggered every 6 months (DR-053)

**`lora_finetune.py`**
- Per-retailer LoRA fine-tune
- LoRA rank 32, attention layers
- Triggered quarterly per retailer (DR-051)

**`qlora_finetune.py`**
- QLoRA fallback when memory constrained

### `ai/evaluation/`

**`golden_set/`** (git-lfs)
- 500 curated (person, garment) pairs
- Stratified by demographic, garment category, pose

**`metrics/`**
- `fid.py` — Fréchet Inception Distance
- `clip_score.py` — CLIP similarity
- `arcface_identity.py` — Face identity preservation
- `bias_score.py` — Per-slice quality breakdown

**`run_eval.py`**
- Runs full eval suite on a model version
- Outputs JSON report with pass/fail vs thresholds

### `ai/configs/`

Hydra configs:
```yaml
# configs/inference/default.yaml
model:
  name: idm-vton
  version: v2.3
  lcm_lora: true
  fp16: true
  flash_attention: true

triton:
  url: ${env:TRITON_URL}
  batch_size: 4
  dynamic_batching: true

pipeline:
  stages:
    - person_preprocessing
    - identity_prep
    - garment_warping
    - diffusion
    - vae_decode
    - face_restoration
    - quality_scoring
    - post_processing
```

### `ai/lora_adapters/` (git-lfs)

```
lora_adapters/
├── base/
│   └── v2.3.safetensors
├── retailers/
│   ├── ret_123/
│   │   ├── 2026Q3.safetensors
│   │   └── metadata.json
│   └── ret_456/
└── categories/
    ├── dress.safetensors
    ├── denim.safetensors
    └── knitwear.safetensors
```

### Model versioning

Every model artifact versioned with:
- Semantic version (v2.3.1)
- Training data hash
- LoRA adapter hash
- Eval results hash
- Triton model repo path

Stored in `model_registry` table in Postgres.

---

# 8. Infrastructure

## 8.1 Docker

Each service has its own `Dockerfile`. Multi-stage builds. Distroless final images.

### Example: `apps/tryon-service/Dockerfile`

```dockerfile
# Build stage
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /tryon-service ./cmd/server

# Runtime stage (distroless)
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /tryon-service /tryon-service
USER nonroot
EXPOSE 8080
ENTRYPOINT ["/tryon-service"]
```

### Example: `ai/Dockerfile`

```dockerfile
FROM nvidia/cuda:12.4.0-runtime-ubuntu22.04
RUN apt-get update && apt-get install -y python3.11 python3-pip
WORKDIR /app
COPY pyproject.toml ./
RUN pip install --no-cache-dir -e .
COPY . .
CMD ["python", "-m", "ai.inference.server"]
```

## 8.2 Docker Compose (local dev)

`infrastructure/docker/docker-compose.yml` runs the full stack locally:

```yaml
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_DB: vto
      POSTGRES_USER: vto
      POSTGRES_PASSWORD: dev
    ports: ["5432:5432"]
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql

  redis:
    image: redis:7-alpine
    ports: ["6379:6379"]

  clickhouse:
    image: clickhouse/clickhouse-server:24.3
    ports: ["8123:8123", "9000:9000"]
    volumes:
      - chdata:/var/lib/clickhouse

  kafka:
    image: confluentinc/cp-kafka:7.6.0
    # ... (with zookeeper or kraft mode)

  triton:
    image: nvcr.io/nvidia/tritonserver:24.03-py3
    runtime: nvidia
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
    volumes:
      - ../../ai/model_repo:/models
    command: tritonserver --model-repository=/models
    ports: ["8000:8000", "8001:8001", "8002:8002"]

  api-gateway:
    build: ../../apps/api-gateway
    ports: ["8080:8080"]
    depends_on: [auth-service, body-service, garment-service, tryon-service]
    environment:
      - REDIS_URL=redis://redis:6379

  # ... all other services

volumes:
  pgdata:
  chdata:
```

`make dev` runs `docker compose up`. Full stack ready in <2 minutes.

## 8.3 Kubernetes (for RunPod burst)

We use ECS Fargate for primary (DR-035). K8s manifests in `infrastructure/kubernetes/` for RunPod burst capacity.

Kustomize structure:
```
infrastructure/kubernetes/
├── base/
│   ├── inference-gateway-deployment.yaml
│   ├── inference-gateway-service.yaml
│   ├── triton-deployment.yaml
│   └── kustomization.yaml
└── overlays/
    ├── runpod-spot/
    └── aws-prod/
```

## 8.4 Terraform

All infrastructure as code. Module-based.

### Module list

```
infrastructure/terraform/modules/
├── vpc/                  # VPC, subnets, NAT, IGW
├── ecs/                  # ECS cluster + service definitions
├── rds/                  # Aurora Postgres
├── elasticache/          # Redis
├── msk/                  # MSK Kafka
├── s3/                   # S3 buckets
├── cloudfront/           # CloudFront distributions
├── kms/                  # KMS keys
├── waf/                  # WAF rules
├── gpu-pool/             # EC2 GPU ASG
├── cloudwatch/           # Alarms + dashboards
├── iam/                  # IAM roles + policies
└── route53/              # DNS
```

### Environments

```
infrastructure/terraform/environments/
├── dev/                  # Single-AZ, minimal
├── staging/              # Multi-AZ, smaller scale
└── production/           # Multi-AZ, multi-region
```

Each environment has:
- `main.tf` — module composition
- `variables.tf` — env-specific inputs
- `terraform.tfvars` — actual values (gitignored; in Secrets Manager)
- `outputs.tf` — useful outputs

### State management

- Terraform state in S3 + DynamoDB lock
- One state file per environment per region
- State access restricted to CI/CD role

## 8.5 GitHub Actions

### `.github/workflows/ci.yml`

Runs on every PR:
1. Lint (per-language)
2. Type check
3. Unit tests
4. Build (all services)
5. SBOM generation
6. Snyk vulnerability scan
7. Semgrep SAST

### `.github/workflows/deploy-staging.yml`

Runs on merge to `main`:
1. Build Docker images
2. Push to ECR with sha + latest tags
3. Terraform plan (staging)
4. Terraform apply (staging)
5. ECS deploy (staging)
6. Smoke tests

### `.github/workflows/deploy-production.yml`

Runs on git tag `v*`:
1. Same as staging but production
2. Requires manual approval
3. Blue/green deployment
4. Auto-rollback on alarm

### `.github/workflows/release.yml`

Runs on git tag `v*`:
1. Build SDKs for all platforms
2. Publish to: CocoaPods, SwiftPM, Maven Central, npm, pub.dev
3. Generate release notes
4. Create GitHub Release

## 8.6 Secrets

- AWS Secrets Manager for all production secrets
- Doppler for local dev secrets (synced to `.env` via `doppler run`)
- `.env` files gitignored; `.env.example` committed
- KMS for encryption at rest
- IAM roles for service-to-service auth (no long-lived keys)

## 8.7 Environment variables

Standardized across all services:

```bash
# Required
ENV=production|staging|dev
AWS_REGION=us-east-1
LOG_LEVEL=info
SENTRY_DSN=https://...

# Service-specific
DATABASE_URL=postgresql://...
REDIS_URL=redis://...
KAFKA_BROKERS=...
S3_BUCKET=...
KMS_KEY_ID=...

# External
STRIPE_API_KEY=...
RESEND_API_KEY=...
AUTH0_DOMAIN=...
```

Loaded via `envconfig` (Go) / `pydantic-settings` (Python) / `zod` (TS).

---

# 9. Coding Standards

## 9.1 Folder naming

- All folders: `kebab-case` (e.g., `body-service`, `tryon-pipeline`)
- Exception: language-idiomatic folders inside packages (e.g., Swift `Sources/`, Kotlin `src/main/kotlin/`)

## 9.2 File naming

- Go: `snake_case.go` (e.g., `body_handler.go`)
- Python: `snake_case.py`
- TypeScript / JavaScript: `kebab-case.ts` or `camelCase.ts` (per existing ecosystem norm)
- Swift: `PascalCase.swift` (e.g., `TryOnSDK.swift`)
- Kotlin: `PascalCase.kt`
- Terraform: `snake_case.tf`

## 9.3 Architecture rules

1. **Services do not share databases.** Each service owns its schema.
2. **Services do not share code.** Shared code goes in `packages/`.
3. **Services communicate via REST (sync) or Kafka (async).** No direct DB access across services.
4. **SDKs do not import backend code.** They import from `packages/contracts` only.
5. **No business logic in API gateway.** It routes and validates only.
6. **AI code is Python.** Backend code is Go. Dashboard is TypeScript. SDKs are platform-native. No exceptions.
7. **No premature abstraction.** If only one service needs it, don't put it in `packages/`.

## 9.4 Dependency rules

```
apps/*           → can import packages/*
sdks/*           → can import packages/contracts, packages/types
ai/*             → can import packages/py-utils
dashboard/*      → can import packages/contracts, packages/types
packages/*       → cannot import apps/* or sdks/*
packages/contracts → cannot import anything internal
```

Enforced by `dependency-cruiser` (TS) and `go-cycle` (Go).

## 9.5 Error handling

- All errors use the canonical error code catalog (`packages/error-codes`)
- Errors are typed (Go: `errors.Is`/`errors.As`; Python: custom exception hierarchy; TS: discriminated unions)
- No `panic` / `throw` for expected errors (e.g., validation). Return error.
- `panic` / `throw` only for programmer errors (e.g., nil pointer, impossible state)
- Every error logged with structured fields (request_id, retailer_id, etc.)

## 9.6 Logging

- Structured JSON logging everywhere (no `fmt.Println`)
- Log levels: `DEBUG`, `INFO`, `WARN`, `ERROR`
- Required fields: `timestamp`, `level`, `service`, `request_id`, `retailer_id` (if applicable)
- No PII in logs (enforced by linter rule)
- Logs shipped to Datadog
- SDK logs are opt-in; default off

## 9.7 Testing

### Test pyramid

```
        ┌───────────┐
        │    E2E    │  5%   (Playwright,跨服务)
        ├───────────┤
        │ Integration│  20%  (testcontainers, real DB)
        ├───────────┤
        │   Unit    │  75%  (mocks for external deps)
        └───────────┘
```

### Coverage requirements

- Business logic: ≥80%
- API handlers: ≥70%
- AI inference code: ≥60% (harder to test)
- SDK code: ≥70%
- Infra code: ≥50%

### Test tools

- Go: `testing` + `testify` + `testcontainers-go`
- Python: `pytest` + `testcontainers`
- TypeScript: `vitest` + `testcontainers`
- Swift: `XCTest`
- Kotlin: `JUnit5` + `MockK`
- E2E: `Playwright`

## 9.8 Documentation

- Every service has a `README.md` with: purpose, how to run, how to test, key endpoints
- Every public API function has a docstring / JSDoc / GoDoc
- Architecture decisions in `docs/architecture/adr/`
- ADRs numbered: `ADR-001-why-we-chose-go.md`
- Runbooks in `docs/runbooks/{service-name}.md`

## 9.9 Branch strategy

- **Trunk-based development.** `main` is always deployable.
- Short-lived feature branches (<3 days)
- PR required to merge to `main`
- Squash and merge
- Conventional commits (below)

## 9.10 Commit convention

Conventional Commits:

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `perf`, `ci`, `build`

Examples:
```
feat(tryon-service): add cache hit metrics
fix(ios-sdk): handle JWT expiry during scan
docs(api): add tryon endpoint examples
ci: add Snyk scan to PR pipeline
```

Enforced by commitlint + commitizen.

## 9.11 Versioning

- **SDKs:** Semantic versioning (v1.2.3). Breaking changes = major bump. Driven by conventional commits.
- **API:** URL-based (`/v1/`). 24-month stability promise (DR-040).
- **Backend services:** Internal versioning; not customer-facing.
- **AI models:** Semantic version (v2.3.1) tied to training data hash.

---

# 10. Development Roadmap

## Milestone 1: Foundation (Weeks 1-4)

**Goal:** Repo structure, CI/CD, local dev environment. Zero business logic.

**Deliverables:**
- Monorepo with Turborepo
- All 14 service scaffolds (compile + run hello world)
- Postgres, Redis, Kafka, ClickHouse running locally via docker-compose
- Terraform for dev environment
- CI/CD pipeline (lint, test, build, deploy staging)
- API gateway routing to all services
- Auth service with JWT issuance
- OpenAPI spec for v1 endpoints
- Generated client libraries (TypeScript, Go, Python)
- Documentation skeleton

**Estimated time:** 4 weeks

**Dependencies:** None (starting point)

**Definition of Done:**
- `make dev` starts full stack in <2 minutes
- `curl localhost:8080/v1/health` returns 200
- CI pipeline passes on PR
- Staging environment auto-deploys on merge to `main`
- New engineer can clone repo and run in <1 hour

---

## Milestone 2: AI Engine MVP (Weeks 5-10)

**Goal:** IDM-VTON running end-to-end. Body scan → try-on image.

**Deliverables:**
- IDM-VTON integrated with Triton
- Body scan pipeline (iPhone LiDAR → SMPL-X fitting)
- Garment digitization pipeline (basic — manual QC for now)
- Try-on pipeline (10 stages, unoptimized)
- Triton Inference Server deployed
- Evaluation framework v0 (CLIP score, FID)
- 50 SKU catalog digitized (test data)
- 20 body profiles (team members)
- Demo: scan → try-on → view image (latency doesn't matter yet)

**Estimated time:** 6 weeks

**Dependencies:** Milestone 1

**Definition of Done:**
- Demo works for 50 SKUs / 20 body profiles
- Try-on image quality "looks reasonable" (informal review)
- Triton deployed and serving
- Cost per try-on tracked (unoptimized, expected ~$0.30)
- Evaluation framework produces JSON report

---

## Milestone 3: Production Hardening (Weeks 11-14)

**Goal:** Latency <2s, cost <$0.05/try-on, security review pass.

**Deliverables:**
- LCM-LoRA integrated (4-step sampling)
- TensorRT compilation for all models
- FP16 + Flash Attention 2
- Dynamic batching in Triton
- Result caching (Redis, 24h TTL)
- Spot instance support (DR-060)
- Cost circuit breaker (DR-023)
- NSFW classifier on inputs + outputs
- Rate limiting (per-tenant, per-IP)
- Pen test (internal)
- Load test: 1000 try-ons/min sustained

**Estimated time:** 4 weeks

**Dependencies:** Milestone 2

**Definition of Done:**
- p95 latency <2s
- Cost per try-on < $0.10 (target $0.05 by pilot)
- Pen test passes with no S0/S1 findings
- Load test sustained for 30 minutes without degradation
- All DR-027/040/061 security controls in place

---

## Milestone 4: iOS SDK + Pilot (Weeks 15-20)

**Goal:** iOS SDK shipped. First retailer in pilot.

**Deliverables:**
- iOS SDK (Swift, all public API methods)
- Body scan flow (iPhone Pro LiDAR)
- Try-on viewer
- Event tracking
- Webhook delivery
- Billing (Stripe integration)
- Analytics dashboard (basic)
- 1 retailer signed (LOI)
- 200 SKUs digitized from retailer
- Pilot launched to 1% of retailer's app users

**Estimated time:** 6 weeks

**Dependencies:** Milestone 3

**Definition of Done:**
- iOS SDK crash-free rate >99.5% in pilot
- 10,000+ try-ons generated
- Retailer dashboard live with real data
- First invoice generated and paid
- Retailer signs annual contract

---

## Milestone 5: Enterprise Scale (Weeks 21-32)

**Goal:** 5+ retailers, SOC 2 Type II, multi-region.

**Deliverables:**
- Android SDK
- Web SDK
- React Native + Flutter wrappers (if demanded)
- EU region deployment (eu-west-1)
- SOC 2 Type II audit started
- Self-serve developer onboarding
- 5+ retailers in production
- $200K+ MRR

**Estimated time:** 12 weeks

**Dependencies:** Milestone 4

**Definition of Done:**
- 5+ retailers live
- $200K MRR
- SOC 2 Type II report published
- Self-serve onboarding: signup to first try-on in <60 min
- EU data residency enforced

---

# 11. First 100 Engineering Tasks

Tasks ordered by execution. Each has: ID, Title, Description, Priority, Estimated time, Dependencies, Owner, Acceptance criteria.

## Milestone 1 — Foundation (Tasks 1-40)

### Task 1: Initialize monorepo with Turborepo
- **Description:** Set up `package.json` workspace, `turbo.json`, `pnpm-workspace.yaml`. Configure task graph caching.
- **Priority:** P0
- **Estimate:** 4h
- **Dependencies:** None
- **Owner:** DevOps
- **Acceptance:** `pnpm install` works; `pnpm build` builds all packages; cache hits on second run

### Task 2: Create top-level folder structure
- **Description:** Create `apps/`, `ai/`, `sdks/`, `dashboard/`, `packages/`, `infrastructure/`, `docs/`, `tests/`, `tools/` per Section 2.
- **Priority:** P0
- **Estimate:** 1h
- **Dependencies:** T1
- **Owner:** DevOps
- **Acceptance:** Folder structure matches spec; `.gitkeep` files in empty folders

### Task 3: Configure `.gitignore` and `.gitattributes`
- **Description:** Ignore node_modules, .env, build artifacts. Configure git-lfs for `ai/lora_adapters/`, `ai/evaluation/golden_set/`, large datasets.
- **Priority:** P0
- **Estimate:** 1h
- **Dependencies:** T2
- **Owner:** DevOps
- **Acceptance:** `git status` clean after setup; LFS tracks correct files

### Task 4: Set up EditorConfig
- **Description:** `.editorconfig` with consistent indentation, line endings, final newline.
- **Priority:** P1
- **Estimate:** 30m
- **Dependencies:** T2
- **Owner:** DevOps
- **Acceptance:** File present; respected by VS Code, JetBrains

### Task 5: Scaffold API Gateway service (Go)
- **Description:** `apps/api-gateway/` with Go module, chi router, `/health` endpoint, Dockerfile, README.
- **Priority:** P0
- **Estimate:** 4h
- **Dependencies:** T2
- **Owner:** Backend
- **Acceptance:** `go run` starts server; `/health` returns 200; Docker image builds

### Task 6: Scaffold Auth Service (Go)
- **Description:** `apps/auth-service/` with Go module, JWT issuance stub, JWKS endpoint stub, Dockerfile.
- **Priority:** P0
- **Estimate:** 4h
- **Dependencies:** T2
- **Owner:** Backend
- **Acceptance:** Service runs; stub endpoints return 200

### Task 7: Scaffold Body Service (Go)
- **Description:** `apps/body-service/` with Go module, basic CRUD stubs, Dockerfile.
- **Priority:** P0
- **Estimate:** 4h
- **Dependencies:** T2
- **Owner:** Backend
- **Acceptance:** Service runs; stub endpoints return 200

### Task 8: Scaffold Garment Service (Go)
- **Description:** `apps/garment-service/` with Go module, basic CRUD stubs, Dockerfile.
- **Priority:** P0
- **Estimate:** 4h
- **Dependencies:** T2
- **Owner:** Backend
- **Acceptance:** Service runs; stub endpoints return 200

### Task 9: Scaffold Try-On Service (Go)
- **Description:** `apps/tryon-service/` with Go module, basic stubs, Dockerfile.
- **Priority:** P0
- **Estimate:** 4h
- **Dependencies:** T2
- **Owner:** Backend
- **Acceptance:** Service runs; stub endpoints return 200

### Task 10: Scaffold Inference Gateway (Go)
- **Description:** `apps/inference-gateway/` with Go module, Triton client stub, Dockerfile.
- **Priority:** P0
- **Estimate:** 4h
- **Dependencies:** T2
- **Owner:** AI
- **Acceptance:** Service runs; can connect to Triton (even if Triton empty)

### Task 11: Scaffold Analytics Service (Go)
- **Description:** `apps/analytics-service/` with Go module, Kafka producer stub, ClickHouse client stub.
- **Priority:** P0
- **Estimate:** 4h
- **Dependencies:** T2
- **Owner:** Backend
- **Acceptance:** Service runs; can produce to Kafka topic

### Task 12: Scaffold Billing Service (Go)
- **Description:** `apps/billing-service/` with Go module, Stripe SDK integration stub.
- **Priority:** P0
- **Estimate:** 4h
- **Dependencies:** T2
- **Owner:** Backend
- **Acceptance:** Service runs; Stripe SDK loads

### Task 13: Scaffold Webhook Service (Go)
- **Description:** `apps/webhook-service/` with Go module, Kafka consumer stub, HTTP delivery stub.
- **Priority:** P0
- **Estimate:** 4h
- **Dependencies:** T2
- **Owner:** Backend
- **Acceptance:** Service runs; consumes from Kafka topic

### Task 14: Scaffold Notification Service (Go)
- **Description:** `apps/notification-service/` with Go module, Resend SDK stub.
- **Priority:** P1
- **Estimate:** 3h
- **Dependencies:** T2
- **Owner:** Backend
- **Acceptance:** Service runs; can send test email in dev

### Task 15: Scaffold Admin Service (Go)
- **Description:** `apps/admin-service/` with Go module, SSO stub.
- **Priority:** P1
- **Estimate:** 3h
- **Dependencies:** T2
- **Owner:** Backend
- **Acceptance:** Service runs; auth middleware present

### Task 16: Scaffold Dashboard API (TypeScript)
- **Description:** `apps/dashboard-api/` with Fastify, TypeScript, JWT validation.
- **Priority:** P0
- **Estimate:** 4h
- **Dependencies:** T2
- **Owner:** Backend
- **Acceptance:** Service runs; `/health` returns 200

### Task 17: Set up Postgres with initial schemas
- **Description:** `infrastructure/docker/init.sql` creating all schemas (`auth`, `body`, `catalog`, `tryon`, `billing`, `webhooks`, `dashboard`, `public`). Empty tables.
- **Priority:** P0
- **Estimate:** 6h
- **Dependencies:** T2
- **Owner:** Backend
- **Acceptance:** Postgres container starts; `\dn` shows all schemas

### Task 18: Set up database migration tool
- **Description:** Use `golang-migrate`. Create `migrations/` folder with initial migration creating all tables per Section 4.
- **Priority:** P0
- **Estimate:** 8h
- **Dependencies:** T17
- **Owner:** Backend
- **Acceptance:** `migrate up` creates all tables; `migrate down` drops them

### Task 19: Configure Redis
- **Description:** Add Redis to docker-compose. Document key schema in `docs/`.
- **Priority:** P0
- **Estimate:** 2h
- **Dependencies:** T2
- **Owner:** DevOps
- **Acceptance:** Redis container starts; `redis-cli ping` returns PONG

### Task 20: Configure Kafka (MSK locally)
- **Description:** Add Kafka to docker-compose (Confluent image). Define topics: `events`, `webhooks`, `billing`, `training`.
- **Priority:** P0
- **Estimate:** 4h
- **Dependencies:** T2
- **Owner:** DevOps
- **Acceptance:** Kafka starts; `kafka-topics --list` shows all topics

### Task 21: Configure ClickHouse
- **Description:** Add ClickHouse to docker-compose. Create `analytics.events` table + materialized view per Section 4.
- **Priority:** P0
- **Estimate:** 3h
- **Dependencies:** T2
- **Owner:** DevOps
- **Acceptance:** ClickHouse starts; `SELECT 1` works

### Task 22: Write docker-compose.yml for full local stack
- **Description:** Combine all services + dependencies. Healthchecks. Volume mounts.
- **Priority:** P0
- **Estimate:** 8h
- **Dependencies:** T5-T16, T17-T21
- **Owner:** DevOps
- **Acceptance:** `docker compose up` starts everything; all healthchecks pass

### Task 23: Create Makefile
- **Description:** Top-level commands: `make dev`, `make test`, `make build`, `make lint`, `make migrate`, `make seed`, `make clean`.
- **Priority:** P0
- **Estimate:** 2h
- **Dependencies:** T22
- **Owner:** DevOps
- **Acceptance:** All make targets work

### Task 24: Seed data script
- **Description:** `infrastructure/scripts/seed-local-db.sh` populating: 1 retailer, 5 dashboard users, 50 SKUs, 10 body profiles.
- **Priority:** P1
- **Estimate:** 4h
- **Dependencies:** T18
- **Owner:** Backend
- **Acceptance:** Script runs; data in DB; dashboard can display

### Task 25: OpenAPI spec v1
- **Description:** `packages/contracts/openapi.yaml` with all endpoints per Section 5.
- **Priority:** P0
- **Estimate:** 16h
- **Dependencies:** T2
- **Owner:** Backend
- **Acceptance:** Spec validates in Swagger Editor; imports in Postman

### Task 26: Generate TypeScript client from OpenAPI
- **Description:** Use `openapi-typescript-codegen`. Output in `packages/contracts/generated/typescript/`.
- **Priority:** P0
- **Estimate:** 3h
- **Dependencies:** T25
- **Owner:** Backend
- **Acceptance:** Generated client compiles; can call stub endpoints

### Task 27: Generate Go client from OpenAPI
- **Description:** Use `oapi-codegen`. Output in `packages/contracts/generated/go/`.
- **Priority:** P0
- **Estimate:** 3h
- **Dependencies:** T25
- **Owner:** Backend
- **Acceptance:** Generated client compiles; can call stub endpoints

### Task 28: Generate Python client from OpenAPI
- **Description:** Use `openapi-python-client`. Output in `packages/contracts/generated/python/`.
- **Priority:** P1
- **Estimate:** 3h
- **Dependencies:** T25
- **Owner:** AI
- **Acceptance:** Generated client compiles; can call stub endpoints

### Task 29: Implement JWT issuance in Auth Service
- **Description:** RS256 signing, JWKS endpoint, token revocation list in Redis.
- **Priority:** P0
- **Estimate:** 8h
- **Dependencies:** T6, T18, T19
- **Owner:** Backend
- **Acceptance:** Can mint token; verify via JWKS; revoke works

### Task 30: Implement API key CRUD in Auth Service
- **Description:** Hash storage (SHA-256), prefix-based identification, rotation, revocation.
- **Priority:** P0
- **Estimate:** 6h
- **Dependencies:** T29
- **Owner:** Backend
- **Acceptance:** Create/list/revoke API keys via API

### Task 31: Implement consent recording in Auth Service
- **Description:** Per-scan biometric consent with signature, versioning, audit trail.
- **Priority:** P0
- **Estimate:** 4h
- **Dependencies:** T29
- **Owner:** Backend
- **Acceptance:** Consent recorded; retrievable; revocable

### Task 32: Implement JWT validation middleware in API Gateway
- **Description:** Fetch JWKS, validate tokens, extract claims, set retailer_id on context.
- **Priority:** P0
- **Estimate:** 6h
- **Dependencies:** T5, T29
- **Owner:** Backend
- **Acceptance:** Protected endpoints reject invalid tokens; accept valid ones

### Task 33: Implement rate limiting in API Gateway
- **Description:** Redis-backed sliding window rate limiter. Per-IP, per-tenant, per-endpoint limits.
- **Priority:** P0
- **Estimate:** 8h
- **Dependencies:** T5, T19
- **Owner:** Backend
- **Acceptance:** Rate limit enforced; 429 with `Retry-After` header

### Task 34: Set up Terraform for dev environment
- **Description:** `infrastructure/terraform/environments/dev/` with VPC, ECS, RDS, ElastiCache, MSK, S3.
- **Priority:** P0
- **Estimate:** 16h
- **Dependencies:** T2
- **Owner:** DevOps
- **Acceptance:** `terraform apply` provisions dev environment

### Task 35: Set up ECR repositories
- **Description:** One ECR repo per service. Lifecycle policy: keep last 10 images.
- **Priority:** P0
- **Estimate:** 2h
- **Dependencies:** T34
- **Owner:** DevOps
- **Acceptance:** ECR repos exist; lifecycle policy applied

### Task 36: CI pipeline (lint + test + build)
- **Description:** `.github/workflows/ci.yml` running on PR. Per-language linters, tests, Docker builds.
- **Priority:** P0
- **Estimate:** 12h
- **Dependencies:** T5-T16
- **Owner:** DevOps
- **Acceptance:** PR triggers CI; all checks must pass to merge

### Task 37: Staging deploy pipeline
- **Description:** `.github/workflows/deploy-staging.yml` on merge to main. Build → push ECR → terraform apply → ECS deploy.
- **Priority:** P0
- **Estimate:** 12h
- **Dependencies:** T34, T35, T36
- **Owner:** DevOps
- **Acceptance:** Merge to main triggers staging deploy; smoke tests pass

### Task 38: Set up Sentry for error tracking
- **Description:** Sentry DSN per service. SDK integration in Go, Python, TypeScript.
- **Priority:** P1
- **Estimate:** 4h
- **Dependencies:** T5-T16
- **Owner:** DevOps
- **Acceptance:** Errors appear in Sentry dashboard

### Task 39: Set up Datadog for metrics
- **Description:** Datadog agent in ECS tasks. Custom business metrics emitted.
- **Priority:** P1
- **Estimate:** 6h
- **Dependencies:** T37
- **Owner:** DevOps
- **Acceptance:** Metrics visible in Datadog dashboard

### Task 40: Write onboarding doc
- **Description:** `docs/onboarding/README.md` — clone, install, run, test, deploy. New engineer productive in <1 day.
- **Priority:** P1
- **Estimate:** 4h
- **Dependencies:** T23, T37
- **Owner:** Backend
- **Acceptance:** New engineer follows doc; runs full stack in <1 hour

## Milestone 2 — AI Engine MVP (Tasks 41-65)

### Task 41: Set up Triton Inference Server
- **Description:** Docker image, model repository structure, config files. Local + dev environment.
- **Priority:** P0
- **Estimate:** 8h
- **Dependencies:** T22
- **Owner:** AI
- **Acceptance:** Triton running; `/v2/health/ready` returns 200

### Task 42: Integrate IDM-VTON model
- **Description:** Convert IDM-VTON PyTorch model to ONNX, then Triton model repo. Config: max_batch_size, dynamic_batching.
- **Priority:** P0
- **Estimate:** 16h
- **Dependencies:** T41
- **Owner:** AI
- **Acceptance:** Can submit inference request to Triton; get result

### Task 43: Implement person preprocessing pipeline
- **Description:** Face detection (RetinaFace), body segmentation (SAM), pose estimation (OpenPose), DensePose. As Triton ensemble.
- **Priority:** P0
- **Estimate:** 16h
- **Dependencies:** T41
- **Owner:** AI
- **Acceptance:** Given person image, outputs all preprocessing results

### Task 44: Implement garment warping (TPS)
- **Description:** Train or load TPS warping network. Integrate into pipeline.
- **Priority:** P0
- **Estimate:** 12h
- **Dependencies:** T42
- **Owner:** AI
- **Acceptance:** Garment warped to target pose

### Task 45: Implement face preservation (ArcFace + face mask)
- **Description:** ArcFace embedding extraction. Face mask creation for inpaint protection.
- **Priority:** P0
- **Estimate:** 10h
- **Dependencies:** T43
- **Owner:** AI
- **Acceptance:** Face region preserved through diffusion

### Task 46: Implement face restoration fallback (CodeFormer)
- **Description:** CodeFormer integration for cases where face is degraded.
- **Priority:** P1
- **Estimate:** 8h
- **Dependencies:** T45
- **Owner:** AI
- **Acceptance:** Restored face visible; identity preserved

### Task 47: Implement quality scoring (CLIP + ArcFace)
- **Description:** CLIP similarity (garment fidelity), ArcFace cosine (identity), NSFW classifier.
- **Priority:** P0
- **Estimate:** 8h
- **Dependencies:** T42, T45
- **Owner:** AI
- **Acceptance:** Quality score returned with every try-on

### Task 48: Implement VAE decode optimization
- **Description:** TensorRT-compile VAE decoder. FP16.
- **Priority:** P0
- **Estimate:** 6h
- **Dependencies:** T42
- **Owner:** AI
- **Acceptance:** VAE decode <80ms

### Task 49: Implement post-processing (background removal, color correction, WebP)
- **Description:** Final image processing pipeline before CDN upload.
- **Priority:** P0
- **Estimate:** 6h
- **Dependencies:** T42
- **Owner:** AI
- **Acceptance:** WebP image uploaded to S3; signed URL generated

### Task 50: Wire try-on pipeline end-to-end
- **Description:** `ai/inference/pipelines/tryon_pipeline.py` orchestrating all 10 stages.
- **Priority:** P0
- **Estimate:** 12h
- **Dependencies:** T42-T49
- **Owner:** AI
- **Acceptance:** Given body profile + garment SKU, produces try-on image

### Task 51: Implement body scan pipeline (iPhone LiDAR)
- **Description:** Receive scan data, fit SMPL-X, store body profile.
- **Priority:** P0
- **Estimate:** 16h
- **Dependencies:** T41
- **Owner:** AI
- **Acceptance:** Body profile created from scan data; measurements extracted

### Task 52: Implement garment digitization pipeline (basic)
- **Description:** Background removal, segmentation, attribute extraction, fabric classification.
- **Priority:** P0
- **Estimate:** 16h
- **Dependencies:** T41
- **Owner:** AI
- **Acceptance:** Given SKU photos, produces digitized representation

### Task 53: Implement Inference Gateway client
- **Description:** `apps/inference-gateway/` real implementation: submit jobs to Triton, track status, handle failures.
- **Priority:** P0
- **Estimate:** 12h
- **Dependencies:** T10, T50
- **Owner:** AI
- **Acceptance:** Try-On Service can submit jobs via Inference Gateway

### Task 54: Implement Body Service real logic
- **Description:** Profile CRUD, encrypted storage, KMS integration, expiry enforcement.
- **Priority:** P0
- **Estimate:** 12h
- **Dependencies:** T7, T51
- **Owner:** Backend
- **Acceptance:** Full body profile lifecycle works via API

### Task 55: Implement Garment Service real logic
- **Description:** SKU CRUD, digitization status tracking, async digitization trigger.
- **Priority:** P0
- **Estimate:** 12h
- **Dependencies:** T8, T52
- **Owner:** Backend
- **Acceptance:** Push SKU → digitization triggers → status updates

### Task 56: Implement Try-On Service real logic
- **Description:** Try-on request handling, cache check, job submission, status polling, webhook fire, billing event.
- **Priority:** P0
- **Estimate:** 16h
- **Dependencies:** T9, T53, T54, T55
- **Owner:** Backend
- **Acceptance:** Full try-on flow works end-to-end

### Task 57: Implement result caching (Redis)
- **Description:** Cache key = hash(profile_id, sku, size, view). 24h TTL. Cache hit → skip inference.
- **Priority:** P0
- **Estimate:** 6h
- **Dependencies:** T56
- **Owner:** Backend
- **Acceptance:** Repeat try-on within 24h served from cache

### Task 58: Implement Analytics Service event ingestion
- **Description:** `POST /v1/events` handler. Kafka producer. Idempotency dedup.
- **Priority:** P0
- **Estimate:** 10h
- **Dependencies:** T11, T20
- **Owner:** Backend
- **Acceptance:** Events stored in Kafka; dedup works

### Task 59: Implement Analytics stream processor
- **Description:** Kafka consumer → ClickHouse. Python Faust/Bytewax.
- **Priority:** P0
- **Estimate:** 10h
- **Dependencies:** T58, T21
- **Owner:** AI
- **Acceptance:** Events flow from Kafka to ClickHouse

### Task 60: Implement analytics query API
- **Description:** `GET /v1/analytics/*` endpoints. ClickHouse queries.
- **Priority:** P0
- **Estimate:** 10h
- **Dependencies:** T59
- **Owner:** Backend
- **Acceptance:** Dashboard can fetch summary, funnel, top SKUs

### Task 61: Build evaluation framework v0
- **Description:** `ai/evaluation/run_eval.py`. CLIP score, FID, ArcFace identity. Run on model change.
- **Priority:** P0
- **Estimate:** 12h
- **Dependencies:** T50
- **Owner:** AI
- **Acceptance:** Run produces JSON report with metrics

### Task 62: Curate 100-pair golden eval set (initial)
- **Description:** 100 (person, garment) pairs, diverse. Stored in `ai/evaluation/golden_set/` (git-lfs).
- **Priority:** P0
- **Estimate:** 8h
- **Dependencies:** T50
- **Owner:** AI
- **Acceptance:** 100 pairs committed; eval runs against them

### Task 63: Deploy AI stack to dev environment
- **Description:** Triton + inference-gateway on GPU instance (g5.xlarge). Terraform module.
- **Priority:** P0
- **Estimate:** 8h
- **Dependencies:** T34, T41
- **Owner:** DevOps
- **Acceptance:** Dev environment runs full AI pipeline

### Task 64: Demo: scan → try-on → view
- **Description:** End-to-end demo for 50 SKUs / 20 body profiles. Documentation.
- **Priority:** P0
- **Estimate:** 8h
- **Dependencies:** T56, T51, T52
- **Owner:** AI
- **Acceptance:** Demo works; quality "reasonable"

### Task 65: Cost tracking per inference
- **Description:** Log GPU time per inference. Aggregate to cost per try-on metric.
- **Priority:** P1
- **Estimate:** 6h
- **Dependencies:** T53
- **Owner:** AI
- **Acceptance:** Dashboard shows cost per try-on

## Milestone 3 — Production Hardening (Tasks 66-80)

### Task 66: Integrate LCM-LoRA
- **Description:** Load LCM-LoRA adapter. Reduce sampling from 30 to 4 steps.
- **Priority:** P0
- **Estimate:** 8h
- **Dependencies:** T42
- **Owner:** AI
- **Acceptance:** Sampling 4 steps; CLIP regression <5%

### Task 67: TensorRT compile all models
- **Description:** Compile IDM-VTON, SAM, OpenPose, ArcFace to TensorRT engines. FP16.
- **Priority:** P0
- **Estimate:** 16h
- **Dependencies:** T42
- **Owner:** AI
- **Acceptance:** All models running as TensorRT engines; latency measured

### Task 68: Integrate Flash Attention 2
- **Description:** Replace standard attention in IDM-VTON with FA2.
- **Priority:** P0
- **Estimate:** 6h
- **Dependencies:** T42
- **Owner:** AI
- **Acceptance:** FA2 active; latency reduced

### Task 69: Configure Triton dynamic batching
- **Description:** Batch up to 4 requests, 50ms wait window.
- **Priority:** P0
- **Estimate:** 4h
- **Dependencies:** T41
- **Owner:** AI
- **Acceptance:** Batching active; throughput 3x

### Task 70: Implement spot instance support
- **Description:** Inference Gateway handles spot reclamation: checkpoint, resume, on-demand fallback.
- **Priority:** P0
- **Estimate:** 12h
- **Dependencies:** T53
- **Owner:** DevOps
- **Acceptance:** Spot reclamation test passes; jobs resume

### Task 71: Implement cost circuit breaker
- **Description:** Hard cap at 30% of revenue (DR-023). Auto-throttle inference autoscaler.
- **Priority:** P0
- **Estimate:** 8h
- **Dependencies:** T65
- **Owner:** Backend
- **Acceptance:** When cap hit, autoscaler throttles; alert fires

### Task 72: Implement NSFW classifier on inputs
- **Description:** Body scan input check. Reject NSFW before processing.
- **Priority:** P0
- **Estimate:** 8h
- **Dependencies:** T54
- **Owner:** AI
- **Acceptance:** NSFW scans rejected with clear error

### Task 73: Implement NSFW classifier on outputs
- **Description:** Try-on output check. Block delivery if NSFW detected.
- **Priority:** P0
- **Estimate:** 6h
- **Dependencies:** T56
- **Owner:** AI
- **Acceptance:** NSFW outputs blocked; not billed

### Task 74: Internal pen test
- **Description:** SAST (Semgrep), DAST (ZAP), dependency scan (Snyk). Fix all S0/S1 findings.
- **Priority:** P0
- **Estimate:** 16h
- **Dependencies:** T36
- **Owner:** DevOps
- **Acceptance:** No S0/S1 findings; S2/S3 logged

### Task 75: Load test
- **Description:** k6 script: 1000 try-ons/min for 30 min. Measure p95 latency, error rate.
- **Priority:** P0
- **Estimate:** 12h
- **Dependencies:** T69
- **Owner:** DevOps
- **Acceptance:** p95 <2s; error rate <0.1%

### Task 76: Implement Billing Service real logic
- **Description:** Usage metering from Kafka. Stripe Billing integration. Invoice generation.
- **Priority:** P0
- **Estimate:** 16h
- **Dependencies:** T12, T58
- **Owner:** Backend
- **Acceptance:** Monthly invoice generated; Stripe sync works

### Task 77: Implement Webhook Service real logic
- **Description:** Kafka consumer, HMAC signing, delivery with retries (DR-041), disable after 6 failures.
- **Priority:** P0
- **Estimate:** 12h
- **Dependencies:** T13
- **Owner:** Backend
- **Acceptance:** Webhooks delivered; retries work; disable works

### Task 78: Implement attribution endpoints
- **Description:** `POST /v1/attribution/purchase` and `/return`. Link to try-on.
- **Priority:** P0
- **Estimate:** 8h
- **Dependencies:** T56
- **Owner:** Backend
- **Acceptance:** Attribution recorded; appears in analytics

### Task 79: Curate 500-pair golden eval set
- **Description:** Expand from 100 to 500 pairs, stratified by demographic (DR-056).
- **Priority:** P0
- **Estimate:** 16h
- **Dependencies:** T62
- **Owner:** AI
- **Acceptance:** 500 pairs committed; bias dashboard works

### Task 80: Implement bias evaluation
- **Description:** Per-slice quality breakdown (DR-057). No slice >15% below average.
- **Priority:** P0
- **Estimate:** 10h
- **Dependencies:** T79
- **Owner:** AI
- **Acceptance:** Bias dashboard live; deployment gate enforced

## Milestone 4 — iOS SDK + Pilot (Tasks 81-95)

### Task 81: iOS SDK core
- **Description:** `sdks/ios/` SwiftPM package. Configuration, networking, storage.
- **Priority:** P0
- **Estimate:** 16h
- **Dependencies:** T25
- **Owner:** Mobile
- **Acceptance:** SDK compiles; can configure; can make API call

### Task 82: iOS body scan flow
- **Description:** ARKit LiDAR capture, on-device face masking, quality checks, chunked upload.
- **Priority:** P0
- **Estimate:** 24h
- **Dependencies:** T81
- **Owner:** Mobile
- **Acceptance:** Scan produces body profile; face masked

### Task 83: iOS try-on viewer
- **Description:** Image viewer, swipe between views, share sheet, error states.
- **Priority:** P0
- **Estimate:** 16h
- **Dependencies:** T81
- **Owner:** Mobile
- **Acceptance:** Viewer displays try-on; swipe works

### Task 84: iOS event tracking
- **Description:** SDK fires events; batched; offline queue.
- **Priority:** P0
- **Estimate:** 8h
- **Dependencies:** T81
- **Owner:** Mobile
- **Acceptance:** Events reach analytics service

### Task 85: iOS SDK theming
- **Description:** Retailer-configurable colors, fonts, corner radius.
- **Priority:** P1
- **Estimate:** 8h
- **Dependencies:** T81
- **Owner:** Mobile
- **Acceptance:** Theme applied to all UI components

### Task 86: iOS sample app
- **Description:** `sdks/ios/Example/` demonstrating full integration.
- **Priority:** P0
- **Estimate:** 12h
- **Dependencies:** T81-T84
- **Owner:** Mobile
- **Acceptance:** Sample app runs; full flow demoable

### Task 87: iOS SDK distribution
- **Description:** SwiftPM + CocoaPods. Versioned releases. Documentation.
- **Priority:** P0
- **Estimate:** 8h
- **Dependencies:** T86
- **Owner:** Mobile
- **Acceptance:** Can install via SwiftPM in fresh project

### Task 88: Dashboard frontend (basic)
- **Description:** `dashboard/` Next.js app. Overview, catalog, billing, settings tabs.
- **Priority:** P0
- **Estimate:** 24h
- **Dependencies:** T16, T60, T76
- **Owner:** Backend
- **Acceptance:** Retailer can log in; see metrics; manage catalog

### Task 89: Dashboard SSO (SAML)
- **Description:** Auth0 SAML integration for enterprise retailers.
- **Priority:** P1
- **Estimate:** 8h
- **Dependencies:** T88
- **Owner:** Backend
- **Acceptance:** SSO login works with test IdP

### Task 90: Sign first retailer LOI
- **Description:** Commercial. Not engineering, but blocks everything.
- **Priority:** P0
- **Estimate:** N/A
- **Dependencies:** T64
- **Owner:** CEO (not engineering)
- **Acceptance:** LOI signed

### Task 91: Digitize pilot retailer's 200 SKUs
- **Description:** Run digitization pipeline on real catalog. Manual QC where needed.
- **Priority:** P0
- **Estimate:** 16h
- **Dependencies:** T52, T90
- **Owner:** AI
- **Acceptance:** 200 SKUs digitized; quality >0.8

### Task 92: Integrate SDK into pilot retailer's app
- **Description:** Solutions engineer works with retailer's mobile team. 2-week engagement.
- **Priority:** P0
- **Estimate:** 80h
- **Dependencies:** T87, T91
- **Owner:** Mobile
- **Acceptance:** SDK integrated; in retailer's dev branch

### Task 93: Pilot launch (1% rollout)
- **Description:** Retailer ships to 1% of app users. Monitor.
- **Priority:** P0
- **Estimate:** 8h
- **Dependencies:** T92
- **Owner:** Backend
- **Acceptance:** Try-ons generating; metrics in dashboard

### Task 94: Pilot monitoring + optimization
- **Description:** Daily review. Fix issues. Optimize scan completion, try-on success.
- **Priority:** P0
- **Estimate:** 40h (2 weeks)
- **Dependencies:** T93
- **Owner:** Backend
- **Acceptance:** Metrics trending positive; retailer satisfied

### Task 95: First invoice + retailer contract
- **Description:** Generate first invoice. Convert pilot to annual contract.
- **Priority:** P0
- **Estimate:** N/A
- **Dependencies:** T94
- **Owner:** CEO (not engineering)
- **Acceptance:** Contract signed; invoice paid

## Milestone 5 — Enterprise Scale (Tasks 96-100)

### Task 96: Android SDK
- **Description:** `sdks/android/` Kotlin SDK. Mirror of iOS API. ARCore + 2-photo fallback.
- **Priority:** P0
- **Estimate:** 80h
- **Dependencies:** T81 (for API parity reference)
- **Owner:** Mobile
- **Acceptance:** Android SDK feature-parity with iOS; sample app works

### Task 97: Web SDK
- **Description:** `sdks/web/` TypeScript SDK. WebXR + webcam fallback.
- **Priority:** P0
- **Estimate:** 60h
- **Dependencies:** T25
- **Owner:** Backend
- **Acceptance:** Web SDK works in Chrome, Safari, Firefox, Edge

### Task 98: EU region deployment
- **Description:** Terraform for eu-west-1. Data residency enforcement. GDPR DSAR automation.
- **Priority:** P0
- **Estimate:** 40h
- **Dependencies:** T34
- **Owner:** DevOps
- **Acceptance:** EU shoppers' data stays in eu-west-1

### Task 99: SOC 2 Type II audit
- **Description:** Engage auditor. Implement controls. Evidence collection.
- **Priority:** P0
- **Estimate:** 80h (over 3 months)
- **Dependencies:** T74
- **Owner:** DevOps
- **Acceptance:** SOC 2 Type II report published

### Task 100: Self-serve developer onboarding
- **Description:** Signup flow, sandbox provisioning, docs, sample app. Signup to first try-on in <60 min.
- **Priority:** P0
- **Estimate:** 60h
- **Dependencies:** T88, T99
- **Owner:** Backend
- **Acceptance:** New developer can self-serve; first try-on in <60 min

---

# 12. Decision Register Update

New implementation-phase decisions (DR-071 through DR-085) appended to `/home/z/my-project/decision_register.md`:

- **DR-071** — Monorepo with Turborepo (not Bazel, not polyrepo)
- **DR-072** — Go for backend services, Python for AI, TypeScript for dashboard
- **DR-073** — PostgreSQL Aurora as primary OLTP
- **DR-074** — ClickHouse Cloud for analytics (DR-034 reaffirmed for implementation)
- **DR-075** — Schema-per-tenant via `retailer_id` foreign key + RLS (not separate schemas per tenant — refinement of DR-008)
- **DR-076** — Triton Inference Server as model orchestrator (DR-050 reaffirmed)
- **DR-077** — Terraform for all infrastructure; no manual AWS changes
- **DR-078** — Trunk-based development; conventional commits; squash and merge
- **DR-079** — Test pyramid: 75% unit / 20% integration / 5% E2E
- **DR-080** — Sentry for errors, Datadog for metrics, PagerDuty for alerts
- **DR-081** — Distroless Docker images for all Go services
- **DR-082** — golang-migrate for DB migrations
- **DR-083** — OpenAPI 3.1 spec as single source of truth; auto-generate clients
- **DR-084** — AWS Secrets Manager for production secrets; Doppler for dev
- **DR-085** — 5-milestone roadmap: Foundation → AI MVP → Hardening → Pilot → Scale

(Full entries with Evidence Required / Owner / Priority / Status appended to register file.)

---

*End of Production Implementation Blueprint v1.0. Ready for engineering team execution.*
