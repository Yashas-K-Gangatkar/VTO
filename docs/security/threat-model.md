# Threat Model

## System overview

VTO is an enterprise SDK + API platform for AI Virtual Try-On. Retailers integrate our SDK into their existing mobile apps and websites. Shoppers scan their body once, then try on garments virtually.

## Assets

| Asset | Sensitivity | Why it matters |
|-------|-------------|----------------|
| Body scan data (raw mesh) | Biometric (highest) | BIPA/GDPR/CCPA regulated; class-action liability |
| Body profile (SMPL-X params) | Biometric (highest) | Same as raw scan |
| Try-on images | Personal (medium) | Contains shopper's body; 90-day retention |
| Retailer's catalog | Confidential | Retailer's IP |
| Shopper tokens | High | 1h TTL limits blast radius |
| API keys | High | Server-to-server access |
| Model weights (IDM-VTON) | Critical IP | The company's core technology |
| Outcome dataset | Critical IP | The moat (DR-054) |

## Adversaries

| Adversary | Capability | Motivation |
|-----------|-----------|------------|
| Shopper | Has own device, can tamper with SDK | Curiosity; abuse free try-ons |
| Retailer employee | Has dashboard access; limited API access | Curiosity; data theft |
| Competitor | API probing; reverse engineering | Steal IP; benchmark |
| Hacker | DDoS; credential stuffing; SQL injection | Extortion; reputation damage |
| Nation-state | APT; supply chain | Surveillance of citizens |
| Insider (us) | Full system access | Disgruntlement; accident |

## Attack surfaces

### 1. Shopper SDK → Platform API

**Threats:**
- Token theft from device → impersonation
- Adversarial body scan inputs → offensive outputs
- Replay attacks
- Prompt injection (not applicable — no text inputs)

**Mitigations:**
- Tokens are 1h TTL, scoped (DR-027)
- NSFW classifier on all inputs and outputs (DR-061)
- Idempotency keys prevent replays
- No text inputs accepted (eliminates prompt injection)
- Rate limited per-IP and per-tenant

### 2. Retailer backend → Platform API (server-to-server)

**Threats:**
- API key leak from retailer backend → unauthorized access
- Token minting abuse → mint tokens for non-customers
- Excessive requests → DDoS

**Mitigations:**
- API keys are SHA-256 hashed at rest; never logged
- Rate limited per-tenant (DR-040)
- Anomaly detection on token minting rate
- Retailer can rotate keys via dashboard
- Audit log on every API call

### 3. Body scan data at rest

**Threats:**
- Data breach exposing body profiles
- Insider access to shopper data
- Subpoena / government request

**Mitigations:**
- AES-256 at rest via AWS KMS customer-managed keys (DR-011)
- Per-retailer encryption keys
- Row-Level Security enforces tenant isolation (DR-075)
- No bulk export endpoint
- Audit log on every access
- Raw scans deleted within 24h of profile creation
- Body profiles expire after 12 months by default

### 4. Try-on inference pipeline

**Threats:**
- Model weights exfiltration via API probing
- Adversarial inputs causing model to leak training data
- GPU exhaustion attack

**Mitigations:**
- Weights never leave GPU instances
- Rate limits prevent extraction attacks (which require thousands of queries)
- Model watermarking on outputs (DR-062)
- Queue depth limits + circuit breaker (DR-023)
- Spot instance reclamation handling (DR-060)

### 5. Webhooks (outbound)

**Threats:**
- Webhook URL spoofing (attacker registers malicious URL)
- Webhook payload interception
- Replay attacks

**Mitigations:**
- HTTPS required for webhook URLs
- HMAC-SHA256 signature on every webhook (DR-027)
- Retailer MUST verify signature (documented prominently)
- Timestamp in signature prevents replay

### 6. Supply chain

**Threats:**
- Malicious PyPI/npm/Go module
- Compromised model weights from HuggingFace
- Compromised base Docker images

**Mitigations:**
- All dependencies version-pinned (lockfiles committed)
- Snyk scans in CI
- SBOM generated per release
- SLSA Level 3 build provenance (target)
- HuggingFace weights scanned before use
- Base images from trusted sources (distroless, official)

## Compliance

| Regulation | Status |
|------------|--------|
| BIPA (Illinois) | Per-scan consent, 12-month retention, audit log (DR-011) |
| GDPR (EU) | Right to access, deletion, portability; EU data residency (DR-019) |
| CCPA (CA) | "Do not sell" honored (we don't sell data); right to delete |
| SOC 2 Type II | Target month 9 (DR-037) |
| ISO 27001 | Target month 12 (DR-037) |
| PCI DSS | N/A — we don't process payments (Stripe does) |
| HIPAA | N/A — body data is not health data |

## Incident response

See `SECURITY.md` for reporting process. Internal runbook in `docs/runbooks/incident-response.md`.

## Review cadence

- Threat model reviewed quarterly
- Pen test quarterly (third party)
- Bug bounty ongoing (HackerOne)
- Architecture review for any new service or major change
