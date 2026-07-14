# Security Policy

## Reporting a vulnerability

**Do not open public GitHub issues for security reports.**

Email: security@vto.example

Include:
- Description of the vulnerability
- Steps to reproduce
- Affected versions
- Potential impact
- Suggested fix (if any)

We will acknowledge within 24 hours and provide a fix timeline within 72 hours. Reporters will be credited in the security advisory (unless they prefer to remain anonymous).

## Supported versions

Only the latest minor release receives security updates.

## Security measures

This codebase follows these security practices (see `docs/decision-register.md`):

- **No secrets in code.** Production secrets in AWS Secrets Manager (DR-084). Dev secrets in Doppler.
- **No `.env` files in Git.** `.gitignore` blocks them. Pre-commit hooks scan for secrets.
- **All APIs require authentication** except `/health` and `/.well-known/jwks.json`.
- **Rate limiting** on all endpoints (DR-027, DR-040).
- **Input validation** on every endpoint (Zod / Pydantic / validator).
- **SQL injection prevention** — parameterized queries only.
- **OWASP Top 10** reviewed annually.
- **SAST** (Semgrep) and **dependency scan** (Snyk) in CI.
- **DAST** (ZAP) on staging weekly.
- **Pen testing** quarterly by third party.
- **Bug bounty** (HackerOne) — payouts up to $25K for critical.
- **SOC 2 Type II** target by month 9 (DR-037).
- **ISO 27001** target by month 12.

## Threat model

See `docs/security/threat-model.md` for the full threat model and mitigations.

## Incident response

- 24/7 on-call via PagerDuty
- P0 incidents (data breach, service down): customer notification within 1 hour
- Post-mortem published to all retailers within 7 days
- SLA credits per MSA for downtime

## Contact

- Security: security@vto.example
- General: support@vto.example
