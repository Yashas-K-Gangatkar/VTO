# ADR-002: Monorepo with Turborepo

## Status
Accepted (DR-071)

## Context
Need to choose between monorepo and polyrepo for a multi-language codebase (Go, Python, TS, Swift, Kotlin).

## Decision
Single Git monorepo with Turborepo for task orchestration.

## Consequences
- Cross-service refactors (API contract changes) touch backend + SDKs + docs in one PR
- Shared types across teams via `packages/`
- Single source of truth for CI/CD and versioning
- New engineer clones one repo, runs `make dev`, has everything
- Trade-off: larger repo size; CI must be path-filtered to avoid running all checks on every PR

## Alternatives Considered
- **Polyrepo:** Rejected — cross-service changes require coordinated PRs across repos; CI drift; onboarding friction
- **Bazel monorepo:** Rejected — operational tax unjustified at our team size; steep learning curve
- **nx monorepo:** Rejected — JavaScript-only; doesn't handle Go/Python/Swift/Kotlin
