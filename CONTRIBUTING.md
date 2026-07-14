# Contributing to VTO

Thank you for contributing to VTO. This document covers the essentials. For full architecture context, see `docs/`.

## Quick start

```bash
git clone <repo-url>
cd vto
make install
make dev
```

New engineer? See `docs/onboarding/README.md` — you should be productive in under an hour.

## Branch strategy

**Trunk-based development.** `main` is always deployable.

- Branch from `main`
- Name branches: `<type>/<short-description>` (e.g., `feat/tryon-caching`, `fix/jwt-expiry`)
- Keep branches short-lived (<3 days)
- One PR per branch
- Squash and merge to `main`
- Delete branch after merge

## Commit convention

We use [Conventional Commits](https://www.conventionalcommits.org/). Enforced by commitlint.

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

**Types:** `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `perf`, `ci`, `build`

**Examples:**
```
feat(tryon-service): add 24h result caching
fix(auth-service): handle expired JWT during scan
docs(api): add tryon endpoint examples
ci: add Snyk scan to PR pipeline
```

Breaking changes:
```
feat(api)!: rename /v1/body to /v1/body_profiles

BREAKING CHANGE: endpoint renamed for clarity. Update SDK clients.
```

## Pull requests

- PRs required to merge to `main`
- Squash and merge
- PR title becomes commit message — follow conventional commits
- Keep PRs under 400 lines (use `#wip` label for larger)
- Required reviews: 1 (peer) for `main`; 2 for security-sensitive paths
- CI must pass: lint, test, build, SAST
- Delete branch after merge

## Code style

- See `.editorconfig` for indentation, line endings
- Go: `gofmt`, `go vet`, `golangci-lint`
- Python: `ruff`, `black`, `mypy --strict`
- TypeScript: `eslint`, `prettier`
- Swift: `swiftlint`, `swift-format`
- Kotlin: `ktlint`

All enforced in CI. Run `make lint` locally before pushing.

## Testing

Test pyramid: 75% unit / 20% integration / 5% E2E.

Coverage targets:
- Business logic: ≥80%
- API handlers: ≥70%
- AI inference: ≥60%
- SDK: ≥70%
- Infra: ≥50%

Run tests: `make test`

## Architecture rules

- Services do not share databases
- Services do not share code (use `packages/`)
- Services communicate via REST (sync) or Kafka (async)
- No business logic in API gateway
- AI code is Python; backend is Go; dashboard is TS; SDKs are platform-native
- No premature abstraction — if only one service uses it, don't put it in `packages/`

See `docs/decision-register.md` for the 85 architectural decisions that govern this codebase.

## Reporting bugs

Open a GitHub issue with:
- Summary
- Steps to reproduce
- Expected vs actual behavior
- Environment (OS, browser, app version)
- Logs (no PII)

## Security reports

**Do not open public issues for security reports.** Email security@vto.example. See `SECURITY.md`.

## License

By contributing, you agree that your contributions are licensed under the project's proprietary license. See `LICENSE`.
