# Startup Decision Register

**Project:** Universal Mobile Virtual Try-On Ecosystem for Physical Retail
**Role:** CTO / Chief AI Scientist / Principal Architect / Eng Lead
**Status:** Phase — Market Validation complete; entering Go-To-Market planning

> Purpose: accumulate architectural and product decisions made across conversations. Every entry must include: ID, date, decision, rationale, alternatives considered, status, and revisit trigger.

---

## DR-001 — Image-based virtual try-on for MVP, defer 3D
- **Date:** 2026-07-10
- **Decision:** MVP uses image-based (diffusion-model) try-on, not 3D garment + cloth simulation.
- **Rationale:** Real-time photorealistic cloth sim on mobile is unsolved. Every shipping competitor (Zeekit, Revery, Fashn) uses image-based. Diffusion-based VITON models (CatVTON, OOTDiffusion) achieve commercially acceptable quality today.
- **Alternatives:** (a) Full 3D pipeline with offline simulation — 12-18 month delay, high GPU cost per render. (b) 2D sprite overlay — looks fake, kills the value prop.
- **Status:** Adopted for MVP.
- **Revisit trigger:** When on-device NPUs (Snapdragon 8 Gen 5+, A18 Pro+) can run real-time cloth sim at <2W, OR when a launch partner demands physically-accurate fit (e.g., tailored clothing).

## DR-002 — Phone-based body scan, not booth, for MVP
- **Date:** 2026-07-10
- **Decision:** MVP body capture uses shopper's own smartphone (iPhone Pro LiDAR first, Android ARCore second). Booth is Phase 2.
- **Rationale:** Booths add CapEx, mall sales cycle, physical maintenance, and floor-space fights — none of which prove product value. Phone-first proves the loop, booth is a premium upsell later.
- **Alternatives:** (a) Mall booths from day 1 — 12-18 month delay to first revenue. (b) Webcam kiosk — privacy nightmare in store.
- **Status:** Adopted for MVP.
- **Revisit trigger:** Mall operator offers to fund booth CapEx and we already have phone-MVP traction.

## DR-003 — iPhone Pro first, Android second
- **Date:** 2026-07-10
- **Decision:** Body scan launches iOS-Pro-only (LiDAR). Android follows 2-3 months later.
- **Rationale:** iPhone Pro LiDAR gives consistent depth; Android depth APIs fragment across 5+ vendors with widely varying quality. Sequential de-risks the CV problem.
- **Alternatives:** (a) Cross-platform launch — Android quality variance drags down MVP perception. (b) Use RGB-only 2D photo approach (3DLOOK-style) — lower accuracy but cross-platform.
- **Status:** Adopted for MVP.
- **Revisit trigger:** If launch partner's shopper demographic skews Android >70%, switch to RGB-only 2-photo approach for parity.

## DR-004 — 2D garment representation (front+back+mask) for MVP
- **Date:** 2026-07-10
- **Decision:** Garment digitization produces 2D representations (front image, back image, segmentation mask, category, attributes) — not 3D garment meshes.
- **Rationale:** 2D representations feed image-based try-on (DR-001). 3D meshes require cloth sim (DR-001 rejected for MVP). 2D is 5-10x cheaper to produce per SKU.
- **Alternatives:** 3D garment meshes (BCNet-class) — needed for Phase 2 3D pipeline.
- **Status:** Adopted for MVP.
- **Revisit trigger:** When 3D try-on pipeline is funded (Phase 2).

## DR-005 — Build vs. buy matrix
- **Date:** 2026-07-10
- **Decision:**
  - **BUILD:** body scan pipeline, try-on model fine-tuning, garment digitization pipeline, mobile app, inference service.
  - **BUY:** QR system (off-the-shelf), CDN (Cloudflare/CloudFront), ML observability (Arize or Evidently), auth (Auth0 or Ory), payments (Stripe).
  - **OPEN:** size recommendation (True Fit partnership vs. build — defer decision until returns data exists).
- **Rationale:** Build where the moat lives (digitization, try-on, body). Buy where the market has commoditized the problem and the build effort has no competitive return.
- **Status:** Adopted.
- **Revisit trigger:** Any build item slipping >2 months should be re-evaluated for buy/partnership.

## DR-006 — SMPL-X as parametric body model
- **Date:** 2026-07-10
- **Decision:** Use SMPL-X (or licensed derivative) as the parametric body model for avatar fitting.
- **Rationale:** Industry standard, well-supported, supports body+hands+face, fits cleanly from scan meshes. Avoids building a custom body parametrization.
- **Alternatives:** (a) Custom body model — years of research, no business value. (b) CAESAR-derived models — older, less expressive. (c) MPM/implicit models — overkill for MVP.
- **Status:** Adopted.
- **Revisit trigger:** Commercial licensing conflict with Max Planck Institute, or strategic need for higher-fidelity hand/face.

## DR-007 — Fine-tune open-source VITON, do not train from scratch
- **Date:** 2026-07-10
- **Decision:** Start from CatVTON or OOTDiffusion (open-source), fine-tune on launch partner's catalog. Do not train a try-on model from scratch.
- **Rationale:** Training from scratch needs millions of paired images and >$500K of GPU spend. Fine-tuning on 5-20K partner SKUs is achievable in 4-6 weeks for <$20K.
- **Alternatives:** (a) Train from scratch — capital waste. (b) License Revery/Fashn API — kills the moat.
- **Status:** Adopted for MVP.
- **Revisit trigger:** When catalog diversity exceeds what fine-tuning can handle (likely 10+ brands, 50K+ SKUs), begin training a custom base model.

## DR-008 — Schema-per-tenant for multi-tenancy
- **Date:** 2026-07-10
- **Decision:** MVP multi-tenancy uses Postgres schema-per-tenant (one schema per brand/mall). Row-level security added in Phase 2.
- **Rationale:** Strong isolation, simpler than RLS at small scale, easy to reason about. Migration to RLS is a Phase 2 refactor when tenant count >50.
- **Alternatives:** (a) Database-per-tenant — operational overhead at scale. (b) RLS from day 1 — more engineering effort for marginal benefit at MVP tenant counts.
- **Status:** Adopted for MVP.
- **Revisit trigger:** Tenant count >50 or any cross-tenant data leak incident.

## DR-009 — AWS as primary cloud, multi-region from day 1
- **Date:** 2026-07-10
- **Decision:** AWS primary (us-east-1 + eu-west-1 from launch). Avoid vendor lock-in for stateless services (containerized).
- **Rationale:** AWS has the deepest GPU inventory (g5/g6), best compliance certifications, and Cloudflare in front gives CDN+WAF portability.
- **Alternatives:** (a) GCP — better TPU story, weaker retail ecosystem. (b) Multi-cloud from day 1 — operational complexity unjustified at MVP.
- **Status:** Adopted.
- **Revisit trigger:** GPU spot availability crisis, or a strategic partner mandates GCP/Azure.

## DR-010 — Defer 3D cloth simulation, fabric physics, lighting realism to Phase 2+
- **Date:** 2026-07-10
- **Decision:** P8 (3D cloth sim), P9 (fabric physics), P10 (lighting realism) are explicitly out of MVP scope.
- **Rationale:** All three are research-grade on mobile. None are required to ship a commercially viable image-based try-on. Funding them in MVP burns runway without moving revenue.
- **Status:** Adopted.
- **Revisit trigger:** Phase 2 funding round, or premium brand partner demands physically-accurate fit.

## DR-011 — Per-scan consent + 30-day auto-purge default for biometric data
- **Date:** 2026-07-10
- **Decision:** Body scans require explicit per-scan consent. Default retention 30 days, customer-extendable to "save my avatar" with separate consent. Delete-on-demand is a hard SLA (≤72h).
- **Rationale:** Body scan data is biometric under BIPA (IL), GDPR Art. 9 (EU), CCPA (CA). Architectural choices that assume long retention will fail compliance review and create tort exposure.
- **Alternatives:** (a) Permanent avatar by default — high compliance risk. (b) Zero retention (compute on-device only) — quality ceiling too low.
- **Status:** Adopted.
- **Revisit trigger:** Customer research shows shoppers abandon app if asked to re-scan; revisit with on-device-only option.

## DR-012 — Warm GPU pool, not serverless, for try-on inference
- **Date:** 2026-07-10
- **Decision:** Try-on inference runs on a warm pool of GPU instances (2-4 at MVP) behind a queue. Not serverless GPU (e.g., Modal, Runpod).
- **Rationale:** Diffusion model cold start is 5-15s. Shoppers will not wait. Warm pool cost is predictable; serverless cold-start UX is unacceptable.
- **Alternatives:** (a) Serverless GPU — fails UX. (b) On-device inference — model too large for mid-range phones in MVP window.
- **Status:** Adopted for MVP.
- **Revisit trigger:** Nighttime traffic drops pool utilization <10%; consider hybrid with scheduled scale-down.

---

## Open questions blocking architecture
- Q1: First committed retail partner profile (drives catalog size, fit sensitivity, integration path).
- Q2: 9-month runway + team size (drives build vs. buy, sequential vs. parallel execution).
- Q3: Geographic launch market (US-only vs. US+EU from day 1 affects GDPR architecture).
- Q4: Brand-exclusivity stance for launch partner (affects multi-tenant isolation decisions).

---

## Decisions Added During Market Validation Phase (2026-07-10)

### DR-013 — Beachhead customer is premium fashion brand, not mall operator
- **Date:** 2026-07-10
- **Decision:** Launch sells to premium fashion brands (Aritzia/Reformation-tier). Mall operators are Phase 2.
- **Rationale:** Mall sales cycles are 9-18 months with indirect ROI. Brand sales cycles are 3-6 months with direct ROI (returns reduction). Beachhead must minimize time-to-revenue.
- **Evidence Required:** Signed LOI from premium brand before seed round.
- **Owner:** CEO (commercial); CTO (technical onboarding).
- **Priority:** P0 — blocks seed raise.
- **Status:** Adopted.
- **Revisit trigger:** If 3+ premium brands reject pilots in 6 months, reconsider mall-led model.

### DR-014 — Hybrid pricing: SaaS + per-try-on + revenue share
- **Date:** 2026-07-10
- **Decision:** Pricing = $300/store/month base + $0.10/try-on over 100/month + 1% revenue share on attributed purchases (capped $500/store/month).
- **Rationale:** Pure SaaS under-monetizes high-usage stores. Pure per-try-on commoditizes. Revenue share aligns incentives and captures upside if we drive real purchases.
- **Evidence Required:** Pilot attribution data showing 5-15% incremental purchase lift per store.
- **Owner:** CEO (pricing); CTO (attribution measurement system).
- **Priority:** P0 — attribution system is critical-path engineering.
- **Status:** Adopted for pilot.
- **Revisit trigger:** If brands reject revenue share terms, fall back to higher SaaS base ($500/store/month).

### DR-015 — Attribution measurement is critical-path engineering
- **Date:** 2026-07-10
- **Decision:** Build attribution system (try-on event → purchase event linkage) from MVP day 1. Not a feature, a foundational capability.
- **Rationale:** Without attribution, we cannot prove ROI, cannot defend pricing, cannot raise Series A. This is the difference between feature and infrastructure.
- **Evidence Required:** Working attribution dashboard for pilot brand by month 3.
- **Owner:** CTO + 1 backend engineer dedicated.
- **Priority:** P0.
- **Status:** Adopted.
- **Revisit trigger:** None — this is foundational.

### DR-016 — Garment digitization pipeline is the strategic moat
- **Date:** 2026-07-10
- **Decision:** Treat P4 (garment digitization) as the company's strategic moat. Try-on inference (P5) is commoditizing and is NOT the moat.
- **Rationale:** Diffusion VITON models commoditize in 18 months. Digitization pipeline + proprietary format + brand data lock-in compounds over years. Every architectural decision should optimize for digitization speed/cost/quality.
- **Evidence Required:** <10 min/SKU human time validated in Track C.
- **Owner:** CTO.
- **Priority:** P0.
- **Status:** Adopted — shapes all architecture decisions.

### DR-017 — Launch partner exclusivity: 12 months for free pilot
- **Date:** 2026-07-10
- **Decision:** Launch brand gets 12-month category exclusivity in exchange for free pilot, free digitization of 200 SKUs, and reference-customer commitment.
- **Rationale:** Reference customer is the single highest-leverage asset for seed raise. Exclusivity compensates brand for being first. 12 months is long enough to lock in advantage, short enough to not block expansion.
- **Evidence Required:** Signed exclusivity agreement.
- **Owner:** CEO.
- **Priority:** P0 — blocks seed raise.
- **Status:** Adopted.
- **Revisit trigger:** If launch brand demands >18 months exclusivity, push back.

### DR-018 — Defer mall operator sales to Phase 2 (year 2+)
- **Date:** 2026-07-10
- **Decision:** Mall operators are not a sales target in year 1. Engage only for booth pilots in year 2+ after brand traction exists.
- **Rationale:** Mall sales cycles consume 9-18 months with no revenue guarantee. Brand traction is the leverage to make mall deals happen faster.
- **Evidence Required:** 3+ paying brand customers before first mall outreach.
- **Owner:** CEO.
- **Priority:** P1.
- **Status:** Adopted.
- **Revisit trigger:** Mall operator inbound with funded booth deployment.

### DR-019 — Defer international expansion to Phase 3 (year 3+)
- **Date:** 2026-07-10
- **Decision:** Year 1 = US-only. Year 2 = US + Canada. Year 3 = add UK/EU. Defer India/APAC to year 4+.
- **Rationale:** GDPR architecture adds complexity. India/APAC retail structure is fundamentally different (organized vs unorganized retail split). US market alone is sufficient to reach $50M ARR.
- **Evidence Required:** $5M US ARR before UK/EU expansion begins.
- **Owner:** CEO.
- **Priority:** P1.
- **Status:** Adopted.
- **Revisit trigger:** Strategic inbound from major UK/EU retailer.

### DR-020 — Kill criteria: Validation Track A failure = company shutdown
- **Date:** 2026-07-10
- **Decision:** If Validation Track A (try-on quality) fails to reach >60% "would skip fitting room" rating across 20 shoppers, kill the company. Do not pivot into online try-on API.
- **Rationale:** Online try-on API market is already commoditized (Fashn, Revery). Pivoting there = entering a red ocean. If physical retail try-on doesn't work, return capital to investors.
- **Evidence Required:** Track A results from 20-shopper study.
- **Owner:** Founders jointly.
- **Priority:** P0.
- **Status:** Adopted — pre-defined kill criteria.

### DR-021 — Position as AI/infrastructure company for investor narrative
- **Date:** 2026-07-10
- **Decision:** Investor narrative = "AI infrastructure for physical retail." NOT "retail tech" or "virtual try-on app."
- **Rationale:** Retail tech is out of investor favor. AI infrastructure is in favor. The digitization pipeline + avatar network + SDK roadmap is genuinely infrastructure, not spin.
- **Evidence Required:** Pitch deck language reviewed by 3+ seed investors.
- **Owner:** CEO.
- **Priority:** P1.
- **Status:** Adopted.
- **Revisit trigger:** If investor feedback suggests retail-tech framing resonates more.

### DR-022 — Reject per-scan and per-active-user pricing models
- **Date:** 2026-07-10
- **Decision:** Per-scan and per-active-user pricing explicitly rejected.
- **Rationale:** Per-scan has near-zero LTV (one-time use). Per-active-user is hard to attribute and brand-resistant. Hybrid (DR-014) is structurally superior.
- **Evidence Required:** None — decision is to reject.
- **Owner:** CEO.
- **Priority:** P2.
- **Status:** Adopted.
- **Revisit trigger:** None.

### DR-023 — Cloud cost circuit breaker: hard cap at 30% of monthly revenue
- **Date:** 2026-07-10
- **Decision:** Hard cap on cloud spend: 30% of trailing 30-day revenue. If cap exceeded, inference autoscaler throttles (degrades latency, not availability).
- **Rationale:** GPU spend is the largest variable cost. Without a circuit breaker, a viral moment or traffic spike can burn 6 months of runway in 30 days.
- **Evidence Required:** Cost monitoring + alerting + auto-throttle live by month 2.
- **Owner:** CTO + 1 infra engineer.
- **Priority:** P0 — required before any production traffic.
- **Status:** Adopted.
- **Revisit trigger:** If cap causes SLA breach with paying customer, revisit pricing.

---

## Decisions Added During Enterprise SDK Pivot (2026-07-10)

### DR-024 — Strategic pivot from consumer app to enterprise SDK + API platform
- **Date:** 2026-07-10
- **Decision:** Company strategy pivots from B2C consumer app to B2B enterprise SDK + API platform. We are no longer building a shopper-facing app; we are a feature embedded inside retailers' existing apps.
- **Rationale:** Consumer app model has high CAC, identity friction, catalog acquisition cost, and checkout complexity. Enterprise SDK eliminates all four. Aligns with Stripe/Firebase/Algolia precedent. Significantly higher revenue per integration ($50K-2M/retailer/yr vs $50-200K/brand/yr).
- **Evidence Required:** Signed LOI from launch retailer committing to SDK integration.
- **Owner:** Founders jointly.
- **Priority:** P0 — defines company.
- **Status:** Adopted. Supersedes DR-013 (beachhead was "premium brand" — now "retailer with mobile app").
- **Revisit trigger:** None — foundational.

### DR-025 — Refined "successful try-on" billing definition
- **Date:** 2026-07-10
- **Decision:** A billable try-on = (1) generation succeeded with valid image returned AND (2) shopper viewed the image (tryon_viewed event fired). Pure generation without view = not billed. Cached re-views within 24h = not billed.
- **Rationale:** Original brief said "pay when successful try-on generated." This is structurally dangerous — we eat 100% of failed generation cost. Refined definition protects us while remaining retailer-friendly. Viewed-event billing aligns with value delivered.
- **Evidence Required:** Event tracking system live with tryon_viewed event; dedup logic tested.
- **Owner:** CTO + Head of Product.
- **Priority:** P0 — defines revenue.
- **Status:** Adopted.
- **Revisit trigger:** If >20% of generated try-ons go unviewed (signals poor retailer UX), reconsider whether to bill on generation.

### DR-026 — Hybrid pricing: $0.15/try-on + $2K/mo minimum commit + $25/SKU digitization
- **Date:** 2026-07-10
- **Decision:** Pricing = $0.15/try-on (tiered to $0.08 at 100K+/mo) + $2K/mo minimum commit + $25/SKU one-time digitization (first 500 SKUs free per retailer). Body scan = free.
- **Rationale:** Pure pay-per-try-on creates adverse selection. Minimum commit is retailer's skin in the game. Body scan free because it's the funnel. Digitization fee covers cost and creates lock-in.
- **Evidence Required:** First 3 paying retailers accept pricing without negotiation.
- **Owner:** CEO.
- **Priority:** P0.
- **Status:** Adopted. Supersedes DR-014 (different model now that retailer pays, not brand).
- **Revisit trigger:** If >50% of prospects reject minimum commit, drop to $1K/mo or remove.

### DR-027 — Three-layer auth: S2S OAuth + scoped SDK tokens + biometric consent
- **Date:** 2026-07-10
- **Decision:** Layer 1: OAuth 2.0 Client Credentials (S2S, retailer backend ↔ platform). Layer 2: scoped short-lived JWT (SDK ↔ platform, 1h TTL, minted by retailer backend). Layer 3: per-scan biometric consent (signed, logged, versioned).
- **Rationale:** Retailer never shares customer credentials with us. Tokens scoped and short-lived. Biometric consent is legally required (BIPA/GDPR/CCPA).
- **Evidence Required:** Auth service live; consent records auditable; external security review passes.
- **Owner:** CTO + 1 security engineer.
- **Priority:** P0.
- **Status:** Adopted.

### DR-028 — Retailer owns shopper identity; we hold opaque shopper_ref only
- **Date:** 2026-07-10
- **Decision:** We store only an opaque shopper reference string (retailer-scoped). No email, no name, no PII. Body profile linked to shopper_ref only.
- **Rationale:** Minimization principle. Reduces compliance surface. Retailer owns relationship; we are processor, not controller, for shopper identity.
- **Evidence Required:** Data schema review confirms no PII storage.
- **Owner:** CTO.
- **Priority:** P0.
- **Status:** Adopted.

### DR-029 — No cross-retailer profile merging by default; portability is opt-in (Phase 2)
- **Date:** 2026-07-10
- **Decision:** Shopper using our try-on in Retailer A and Retailer B gets two separate body profiles. No auto-merge. Phase 2: shopper-initiated "port my profile" flow (consent-gated).
- **Rationale:** Cross-retailer merging without consent violates GDPR. Auto-merging would anger paying retailers. Opt-in portability unlocks network effect without privacy violation.
- **Evidence Required:** Phase 2 design for portability flow.
- **Owner:** CTO + Head of Product.
- **Priority:** P1 (Phase 2).
- **Status:** Adopted.

### DR-030 — iOS SDK first; Android + Web in month 3
- **Date:** 2026-07-10
- **Decision:** MVP ships iOS SDK only. Android and Web SDKs follow in month 3. React Native and Flutter wrappers deferred until community demand.
- **Rationale:** iOS Pro LiDAR gives best body scan quality (DR-003). Retailer launch partners likely skew iOS-Pro in shopper base. Sequential de-risks SDK engineering.
- **Evidence Required:** iOS SDK crash-free rate >99.5% in pilot.
- **Owner:** CTO + Mobile Lead.
- **Priority:** P0.
- **Status:** Adopted.

### DR-031 — React Native + Flutter wrappers deferred
- **Date:** 2026-07-10
- **Decision:** React Native and Flutter wrappers for native SDKs are NOT in MVP. Built only when 3+ retailers request.
- **Rationale:** Wrappers double maintenance burden. Most enterprise retailers have native apps. DTC brands on Shopify use web SDK. Wrappers are nice-to-have, not need-to-have.
- **Evidence Required:** 3+ inbound retailer requests before building.
- **Owner:** CTO.
- **Priority:** P2.
- **Status:** Adopted (deferred).

### DR-032 — Try-on images cached 24h; re-views are free (no rebilling)
- **Date:** 2026-07-10
- **Decision:** Same (body_profile_id, garment_sku, size, view) within 24h = cached result served. Retailer NOT billed for cached re-views.
- **Rationale:** No new compute = no charge. Fair to retailer. Prevents double-billing disputes. 24h TTL balances cache freshness vs. cost.
- **Evidence Required:** Caching layer live; dedup logic tested.
- **Owner:** CTO.
- **Priority:** P0.
- **Status:** Adopted.

### DR-033 — Stripe Billing for invoicing; do not build billing
- **Date:** 2026-07-10
- **Decision:** Use Stripe Billing for invoicing, tax, dunning, payment processing. Do not build custom billing system.
- **Rationale:** Billing is commoditized. Stripe is industry standard. Building billing = wasted engineering time and ongoing maintenance tax.
- **Evidence Required:** Stripe integration live for first pilot.
- **Owner:** CTO + 1 backend engineer.
- **Priority:** P0.
- **Status:** Adopted.

### DR-034 — ClickHouse for analytics (not Snowflake) at v1 scale
- **Date:** 2026-07-10
- **Decision:** ClickHouse Cloud for event analytics and retailer dashboards. Snowflake deferred to Phase 3+.
- **Rationale:** ClickHouse handles sub-second queries on billions of events at 10-20% of Snowflake cost. Snowflake justified only at >$50M ARR with complex BI workloads.
- **Evidence Required:** ClickHouse query performance benchmarks at 100M events.
- **Owner:** CTO + Data Lead.
- **Priority:** P1.
- **Status:** Adopted.

### DR-035 — ECS Fargate (not EKS) until >30 services
- **Date:** 2026-07-10
- **Decision:** Stateless services run on AWS ECS Fargate. Migrate to EKS only when service count >30 or team >20 engineers.
- **Rationale:** Fargate is simpler to operate than K8s at our scale. K8s operational tax unjustified at 12 services. EKS migration is straightforward when needed.
- **Evidence Required:** Service count >30 OR team >20.
- **Owner:** CTO + Infra Lead.
- **Priority:** P1.
- **Status:** Adopted.

### DR-036 — Cloudflare R2 for hot image storage; S3 for cold
- **Date:** 2026-07-10
- **Decision:** Try-on images stored on Cloudflare R2 (zero egress fees) for hot access. S3 for cold/archive storage.
- **Rationale:** R2's zero-egress model saves 30-50% on image delivery costs vs. S3+CloudFront. S3 retained for cold storage where access is rare.
- **Evidence Required:** Cost comparison at 1M+ images stored.
- **Owner:** CTO + Infra Lead.
- **Priority:** P1.
- **Status:** Adopted.

### DR-037 — SOC 2 Type II target by month 9; ISO 27001 by month 12
- **Date:** 2026-07-10
- **Decision:** SOC 2 Type II certification by month 9. ISO 27001 by month 12. Required for enterprise retailer deals.
- **Rationale:** Enterprise retailers (Nordstrom-tier) require SOC 2 for vendor onboarding. EU retailers require ISO 27001. Without these, sales cycle stalls at security review.
- **Evidence Required:** Third-party audit reports.
- **Owner:** CTO + Compliance Lead.
- **Priority:** P0.
- **Status:** Adopted.

### DR-038 — Say-no list: no recommendations, search, loyalty, checkout, reviews
- **Date:** 2026-07-10
- **Decision:** We will NOT build: recommendation engine, search, loyalty, checkout, reviews, customer service chat. These are solved problems with strong incumbents (Algolia, Yotpo, Bazaarvoice, Bloomreach).
- **Rationale:** Feature creep kills SDK integrations. Every added feature is a tax on every retailer integration. We do one thing exceptionally well.
- **Evidence Required:** None — decision is to refuse scope expansion.
- **Owner:** Founders jointly.
- **Priority:** P0 — strategic discipline.
- **Status:** Adopted.

### DR-039 — Self-serve dev onboarding for 80% of integrations
- **Date:** 2026-07-10
- **Decision:** Self-serve developer onboarding (signup → sandbox → first try-on in <60 min) for 80% of retailers. Solutions engineer assigned only for top 20% enterprise.
- **Rationale:** Stripe model. Self-serve scales infinitely; solutions engineers don't. Required for venture-scale distribution.
- **Evidence Required:** 80% of integrations complete without solutions engineer intervention.
- **Owner:** CTO + Head of Developer Experience.
- **Priority:** P0.
- **Status:** Adopted.

### DR-040 — API versioning: URL-based (/v1/); 24-month stability promise
- **Date:** 2026-07-10
- **Decision:** URL-based API versioning (/v1/, /v2/). 24-month minimum stability per major version. 6-month deprecation notice. Field additions non-breaking; field removals breaking.
- **Rationale:** Retailers will not integrate if API breaks unpredictably. Stability promise is a competitive advantage vs. startups with churning APIs.
- **Evidence Required:** Versioning policy published; deprecation process documented.
- **Owner:** CTO.
- **Priority:** P0.
- **Status:** Adopted.

### DR-041 — Webhook retries: 6 attempts over 24h; disable after 6 failures
- **Date:** 2026-07-10
- **Decision:** Webhook delivery retries at 1m, 5m, 30m, 2h, 6h, 24h. After 6 failures, webhook endpoint disabled; retailer notified via dashboard + email.
- **Rationale:** Balances delivery reliability with protection against retailer endpoint that's permanently broken. Disable-and-alert is standard (Stripe, GitHub same pattern).
- **Evidence Required:** Webhook delivery dashboard live; retry policy tested.
- **Owner:** CTO + 1 backend engineer.
- **Priority:** P1.
- **Status:** Adopted.

### DR-042 — Body scan free for retailer; we eat cost (it's the funnel)
- **Date:** 2026-07-10
- **Decision:** Body scan is free for retailers. No per-scan charge. We absorb the compute cost as customer acquisition.
- **Rationale:** Body scan is the funnel — charging for it discourages adoption and reduces try-on volume (which is what we bill for). Free scan = more profiles = more try-ons = more revenue.
- **Evidence Required:** Body scan cost <5% of try-on revenue.
- **Owner:** CTO + CFO.
- **Priority:** P1.
- **Status:** Adopted.
- **Revisit trigger:** If body scan cost >10% of try-on revenue, reconsider.

### DR-043 — Mall operator features removed from roadmap in SDK model
- **Date:** 2026-07-10
- **Decision:** Mall operator sales motion, booth deployment, mall-wide licensing — all removed from roadmap. We sell to retailers with apps, not mall operators.
- **Rationale:** In SDK model, mall operators have no role. Retailers integrate directly. Booths were a consumer-app concept; irrelevant in SDK model.
- **Evidence Required:** None — decision is to remove from roadmap.
- **Owner:** Founders jointly.
- **Priority:** P0 — strategic clarity.
- **Status:** Adopted. Supersedes DR-018 (mall operator deferral — now eliminated entirely).

---

## Decisions Added During AI Engine Architecture Phase (2026-07-10)

### DR-044 — IDM-VTON as v1 base model; FLUX migration in Phase 2
- **Date:** 2026-07-10
- **Decision:** Use IDM-VTON (SD 1.5-based, two-stream architecture) as the v1 production VTON model. Plan migration to FLUX-based VTON in Phase 2 (Month 18) when ecosystem matures.
- **Rationale:** IDM-VTON has best production quality today. SD 1.5 base is well-understood with mature optimization tooling (TensorRT, Flash Attention, LCM-LoRA). FLUX ecosystem (CatVTON-Flux etc.) is immature; migration risk too high for v1.
- **Evidence Required:** IDM-VTON running in production with p95 < 2s; FLUX ecosystem evaluation at Month 12.
- **Owner:** Chief AI Research Scientist.
- **Priority:** P0 — defines the engine.
- **Status:** Adopted.
- **Revisit trigger:** If FLUX-based VTON ecosystem matures faster than expected, accelerate migration.

### DR-045 — Hybrid body representation (SMPL-X + DensePose + keypoints + depth + face)
- **Date:** 2026-07-10
- **Decision:** Use hybrid body representation: SMPL-X as parametric source of truth + DensePose for garment correspondence + 2D keypoints (OpenPose) for IDM-VTON input + depth maps + ArcFace face embeddings for identity preservation.
- **Rationale:** Single representation insufficient. Each captures different signal. IDM-VTON requires keypoints; DensePose improves garment placement 30%; face embedding prevents identity drift.
- **Evidence Required:** Pipeline producing all representations at runtime.
- **Owner:** Chief AI Research Scientist.
- **Priority:** P0.
- **Status:** Adopted.

### DR-046 — Multi-tier body scan: iPhone LiDAR → Android ARCore → 2-photo fallback
- **Date:** 2026-07-10
- **Decision:** Tier 1: iPhone Pro LiDAR scan (gold path, ±1cm). Tier 2: Android ARCore depth (where supported, ±1.5cm). Tier 3: 2-photo RGB fallback (3DLOOK-style, ±2cm).
- **Rationale:** Covers 95% of shoppers with acceptable quality. iPhone-first plays to depth-sensing strength. Fallback ensures broad device coverage.
- **Evidence Required:** Validation Track B passes on iPhone; Android fallback quality >70% acceptance.
- **Owner:** Chief AI Research Scientist + Mobile Lead.
- **Priority:** P0.
- **Status:** Adopted. Supersedes DR-003 (which only said iPhone first; this adds fallback tiers).

### DR-047 — Face masked on-device before upload
- **Date:** 2026-07-10
- **Decision:** Face is detected and masked on the shopper's phone before any image data is uploaded. We never receive raw face data.
- **Rationale:** Privacy minimization. Reduces BIPA/GDPR risk. Reduces data transfer. Forces clean architecture (we render avatars from SMPL-X, not photos).
- **Evidence Required:** On-device face masking in SDK; pen test confirms no face data in transit.
- **Owner:** CTO + Chief AI Research Scientist.
- **Priority:** P0.
- **Status:** Adopted.

### DR-048 — LCM-LoRA for 4-step diffusion sampling
- **Date:** 2026-07-10
- **Decision:** Replace standard 30-step DDIM sampling with 4-step LCM-LoRA consistency model.
- **Rationale:** 4x speedup on diffusion sampling (the pipeline bottleneck). Quality cost ~5-10%, acceptable. Drop-in LoRA adapter, low risk.
- **Evidence Required:** LCM-LoRA integrated; CLIP score regression <5% on golden eval set.
- **Owner:** Chief AI Research Scientist.
- **Priority:** P0 — required for <2s target.
- **Status:** Adopted.

### DR-049 — TensorRT + FP16 + Flash Attention 2 as standard optimization stack
- **Date:** 2026-07-10
- **Decision:** All production models compiled with TensorRT, run in FP16, use Flash Attention 2.
- **Rationale:** Combined ~3x speedup with no quality cost. Industry-standard for diffusion models.
- **Evidence Required:** TensorRT engines built for all models; latency benchmarks confirmed.
- **Owner:** Chief AI Research Scientist + Infra Lead.
- **Priority:** P0.
- **Status:** Adopted.

### DR-050 — Triton Inference Server as model orchestrator
- **Date:** 2026-07-10
- **Decision:** Use NVIDIA Triton Inference Server for model serving, versioning, batching, GPU memory management.
- **Rationale:** Best-in-class for multi-model pipelines. TensorRT integration. Dynamic batching. Alternatives (BentoML, Ray Serve, vLLM) less fit for purpose.
- **Evidence Required:** Triton deployed in production; multi-model pipeline live.
- **Owner:** Infra Lead.
- **Priority:** P0.
- **Status:** Adopted.

### DR-051 — Per-retailer LoRA adapters, quarterly fine-tune
- **Date:** 2026-07-10
- **Decision:** Each retailer gets a LoRA adapter (rank 32) on attention layers, fine-tuned on their catalog + shopper interactions, refreshed quarterly.
- **Rationale:** Captures retailer-specific aesthetic. LoRA (not full fine-tune) is cheap ($50/adapter) and composable with base model at runtime (<5ms swap).
- **Evidence Required:** Per-retailer LoRA training pipeline live; quality lift measured.
- **Owner:** Chief AI Research Scientist.
- **Priority:** P1.
- **Status:** Adopted.

### DR-052 — Per-category LoRA adapters, annual fine-tune
- **Date:** 2026-07-10
- **Decision:** LoRA adapters per garment category (dresses, denim, knitwear, etc.), refreshed annually.
- **Rationale:** Different garment categories have different visual characteristics. Category-specific LoRA stacks with retailer LoRA at runtime.
- **Evidence Required:** Per-category LoRA live for top 5 categories.
- **Owner:** Chief AI Research Scientist.
- **Priority:** P2.
- **Status:** Adopted.

### DR-053 — Base model full fine-tune every 6 months
- **Date:** 2026-07-10
- **Decision:** Full fine-tune of base IDM-VTON every 6 months on aggregated multi-retailer dataset.
- **Rationale:** Captures cross-retailer learnings. Improves base quality over time. Mitigated catastrophic forgetting by including original VITON-HD in fine-tune set.
- **Evidence Required:** Fine-tune run completed; quality lift measured on golden eval set.
- **Owner:** Chief AI Research Scientist.
- **Priority:** P1.
- **Status:** Adopted.

### DR-054 — Real try-on + outcome dataset is the moat (target 1M pairs year 1)
- **Date:** 2026-07-10
- **Decision:** Build proprietary dataset pairing every try-on with metadata (body profile, garment, result, viewed, purchased, returned). Target 1M pairs in year 1, 10M by year 3.
- **Rationale:** This dataset is the strategic moat. No competitor has it. Academic researchers don't have outcome data. Lets us train models that optimize for conversion, not just image quality.
- **Evidence Required:** Data pipeline capturing all outcome events; 1M pairs accumulated by Month 12.
- **Owner:** Chief AI Research Scientist + Data Lead.
- **Priority:** P0 — defines the moat.
- **Status:** Adopted.

### DR-055 — No social media scraping for training data
- **Date:** 2026-07-10
- **Decision:** Explicitly refuse to scrape Instagram, TikTok, or other social media for training data.
- **Rationale:** Legally risky (ToS violations, copyright). Ethically wrong (no consent). PR disaster if discovered. Retailer-provided and consented shopper data only.
- **Evidence Required:** None — decision is to refuse.
- **Owner:** Chief AI Research Scientist + Legal.
- **Priority:** P0.
- **Status:** Adopted.

### DR-056 — Production evaluation set (500 curated pairs, stratified by demographic)
- **Date:** 2026-07-10
- **Decision:** Build golden evaluation set of 500 carefully curated (person, garment) pairs, stratified by body type, skin tone (Fitzpatrick I-VI), garment category, complexity, pose. Run on every model change.
- **Rationale:** VITON-HD doesn't predict real-world performance. Custom eval set calibrated to real retail conditions is essential.
- **Evidence Required:** Golden eval set live; bias monitoring dashboard live.
- **Owner:** Evaluation Engineer (dedicated hire).
- **Priority:** P0.
- **Status:** Adopted.

### DR-057 — Bias evaluation: no slice can score >15% below average
- **Date:** 2026-07-10
- **Decision:** Quality floor: no demographic slice (skin tone, body type, age, gender) can score >15% below overall average. Model not deployed if violated.
- **Rationale:** Model that's great on light-skinned thin subjects but bad on dark-skinned plus-size is a brand and legal liability. Hard floor prevents shipping biased models.
- **Evidence Required:** Bias dashboard live; deployment gate enforced.
- **Owner:** Evaluation Engineer + Chief AI Research Scientist.
- **Priority:** P0.
- **Status:** Adopted.

### DR-058 — AWS primary (g5/g6 fleet) + RunPod burst + Modal for dev
- **Date:** 2026-07-10
- **Decision:** AWS as primary cloud (us-east-1 + eu-west-1) with g5/g6 GPU fleet. RunPod for burst capacity (spot A10s). Modal for ML engineer dev/testing.
- **Rationale:** AWS has best GPU availability, deepest service catalog, strongest compliance. RunPod cheap burst capacity. Modal pay-per-second ideal for dev. Terraform-managed for portability.
- **Evidence Required:** Multi-cloud deployment live; cost per try-on < $0.05.
- **Owner:** Infra Lead.
- **Priority:** P0.
- **Status:** Adopted.

### DR-059 — MacBook Pro M5 Pro + cloud GPU per engineer (no expensive workstations)
- **Date:** 2026-07-10
- **Decision:** Each ML engineer gets MacBook Pro M5 Pro 512GB + $200/month Modal cloud GPU budget. No $8K+ workstations.
- **Rationale:** Cloud GPU revolution has made ML startups viable at low cost. $8K workstation = ~10,000 hours of A100 time. Cloud is cheaper and more flexible.
- **Evidence Required:** Total ML infra cost <$3K/month at 5 engineers.
- **Owner:** CTO.
- **Priority:** P1.
- **Status:** Adopted.

### DR-060 — Spot instance mix: 60% on-demand + 40% spot for production
- **Date:** 2026-07-10
- **Decision:** Production GPU pool is 60% on-demand + 40% spot. Checkpointing + on-demand fallback handles spot reclamation.
- **Rationale:** Spot instances save 70%. Pure spot unacceptable (interruptions). 60/40 mix balances cost and reliability.
- **Evidence Required:** Spot reclamation handling tested; SLA maintained.
- **Owner:** Infra Lead.
- **Priority:** P0.
- **Status:** Adopted.

### DR-061 — NSFW classification on all inputs and outputs
- **Date:** 2026-07-10
- **Decision:** NSFW classifier runs on every body scan input AND every try-on output. NSFW inputs rejected; NSFW outputs blocked from delivery.
- **Rationale:** Retailer liability. Brand safety. Required for App Store compliance.
- **Evidence Required:** NSFW classifier live; false positive rate <2%, false negative rate <0.5%.
- **Owner:** Chief AI Research Scientist.
- **Priority:** P0.
- **Status:** Adopted.

### DR-062 — Model watermarking on all try-on outputs
- **Date:** 2026-07-10
- **Decision:** Embed imperceptible watermark in every try-on output image. Enables detection of model theft / unauthorized reuse.
- **Rationale:** If competitor scrapes our outputs and trains on them, watermark proves theft. Defensive IP measure.
- **Evidence Required:** Watermarking algorithm implemented; survives common image transformations.
- **Owner:** Chief AI Research Scientist.
- **Priority:** P2.
- **Status:** Adopted.

### DR-063 — Differential privacy in fine-tuning (Phase 2)
- **Date:** 2026-07-10
- **Decision:** Add gradient noise during fine-tuning to provide differential privacy guarantees. Phase 2 implementation.
- **Rationale:** Defends against model inversion attacks (reconstructing training data from model). Not critical for v1, important as we scale.
- **Evidence Required:** DP-SGD fine-tuning pipeline; utility/privacy tradeoff benchmarked.
- **Owner:** Chief AI Research Scientist.
- **Priority:** P2 (Phase 2).
- **Status:** Deferred.

### DR-064 — Roadmap: Prototype (M1-2), Alpha (M3-4), Pilot (M5-7), Production (M8-12)
- **Date:** 2026-07-10
- **Decision:** AI engine roadmap: Prototype (Month 1-2, demo works), Internal Alpha (Month 3-4, optimized engine), Retail Pilot (Month 5-7, first retailer live), Enterprise Production (Month 8-12, 5+ retailers + SOC2).
- **Rationale:** Sequential de-risking. Each phase has explicit exit criteria. No skipping.
- **Evidence Required:** Phase exit criteria met before next phase begins.
- **Owner:** Chief AI Research Scientist + CTO.
- **Priority:** P0.
- **Status:** Adopted.

### DR-065 — Catalog digitization: 85-90% automated, 10-15% human QC
- **Date:** 2026-07-10
- **Decision:** Digitization pipeline targets 85-90% full automation. 10-15% flagged for human QC. Human QC tool required.
- **Rationale:** 100% automation unrealistic for complex garments. Human-in-the-loop QC tooling is part of the moat (competitors can copy ML models, not the QC system).
- **Evidence Required:** Auto QC flagging accuracy >80%.
- **Owner:** Chief AI Research Scientist.
- **Priority:** P0.
- **Status:** Adopted.

### DR-066 — Garment preprocessing cached at digitization time, not per try-on
- **Date:** 2026-07-10
- **Decision:** Background removal, segmentation, attribute extraction, fabric classification all run once at digitization time and cached. Per-try-on only computes pose-dependent occlusion masks.
- **Rationale:** Per-try-on latency budget too tight to redo static preprocessing. Caching saves ~600ms per try-on.
- **Evidence Required:** Cache hit rate >95% for digitized SKUs.
- **Owner:** Chief AI Research Scientist.
- **Priority:** P0.
- **Status:** Adopted.

### DR-067 — Predictive precompute when shopper opens PDP (heuristic-gated)
- **Date:** 2026-07-10
- **Decision:** When shopper opens a PDP, precompute try-on (if cache miss likely). Heuristic gate: shopper viewed >3 PDPs in session.
- **Rationale:** 2x perceived speedup (instant result when shopper taps button). Pays for precompute only when likely to be used.
- **Evidence Required:** Precompute hit rate >40%; cost impact <20% of inference budget.
- **Owner:** Chief AI Research Scientist.
- **Priority:** P1.
- **Status:** Adopted.

### DR-068 — Cloud cost target: $0.02-0.05 per try-on
- **Date:** 2026-07-10
- **Decision:** Production target: $0.02-0.05 per try-on cloud cost. At $0.15 price (default tier), this delivers 67-87% gross margin.
- **Rationale:** Required for venture-scale unit economics. Achievable through full optimization stack (Section 8 of AI architecture doc).
- **Evidence Required:** Production cost per try-on measured monthly; trend toward $0.03.
- **Owner:** Chief AI Research Scientist + Infra Lead.
- **Priority:** P0.
- **Status:** Adopted.

### DR-069 — H100 fleet for FP8 inference (Phase 2)
- **Date:** 2026-07-10
- **Decision:** Add H100 instances for FP8 inference in Phase 2. A10 fleet stays on FP16.
- **Rationale:** FP8 on Hopper delivers 2x speedup over FP16 on A10. Worth the cost for high-traffic retailers. Mixed fleet (A10 baseline + H100 premium) optimal.
- **Evidence Required:** H100 FP8 inference benchmarks; cost-per-try-on comparison.
- **Owner:** Chief AI Research Scientist + Infra Lead.
- **Priority:** P1 (Phase 2).
- **Status:** Deferred.

### DR-070 — On-device distilled model for premium tier (Phase 3)
- **Date:** 2026-07-10
- **Decision:** Distill IDM-VTON to mobile-runnable size for on-device inference. Phase 3 (Year 2+). Premium tier only.
- **Rationale:** On-device inference eliminates GPU cost (90% savings) and latency (sub-500ms). Quality cost significant; only acceptable for premium tier with fallback to server-side.
- **Evidence Required:** Distilled model quality >80% of full model; runs on A18 Pro+ at <2W.
- **Owner:** Chief AI Research Scientist.
- **Priority:** P2 (Phase 3).
- **Status:** Deferred.

---

## Decisions Added During Production Implementation Blueprint Phase (2026-07-10)

### DR-071 — Monorepo with Turborepo
- **Date:** 2026-07-10
- **Decision:** Single Git repository with Turborepo for task orchestration. Polyrepo rejected. Bazel rejected as overkill.
- **Rationale:** Cross-service refactors are common (API contract changes touch backend + SDKs + docs). Shared types across teams. Single source of truth for CI/CD. Turborepo handles multi-language workspaces (Go, Python, TS, Swift, Kotlin) better than nx (JS-only) or Bazel (operational overhead).
- **Evidence Required:** Turborepo config live; task graph caching verified.
- **Owner:** Principal Software Architect.
- **Priority:** P0.
- **Status:** Adopted.

### DR-072 — Language assignments: Go (backend), Python (AI), TypeScript (dashboard)
- **Date:** 2026-07-10
- **Decision:** Backend services in Go. AI engine in Python. Dashboard in TypeScript (Next.js). SDKs in platform-native languages (Swift, Kotlin, TS). No exceptions.
- **Rationale:** Go for backend: performance, concurrency, deployability (distroless binaries). Python for AI: ecosystem (PyTorch, Triton client). TS for dashboard: rich ecosystem, fast iteration. Mixing languages within a layer creates maintenance tax.
- **Evidence Required:** All services in assigned language; no exceptions.
- **Owner:** Principal Software Architect.
- **Priority:** P0.
- **Status:** Adopted.

### DR-073 — PostgreSQL Aurora as primary OLTP
- **Date:** 2026-07-10
- **Decision:** AWS Aurora PostgreSQL 16 as primary transactional database. Multi-AZ in production.
- **Rationale:** Industry standard. Managed (no DBA needed). Multi-AZ HA. Read replicas for analytics reads. Aurora Serverless considered and rejected (performance variability).
- **Evidence Required:** Aurora cluster live in dev/staging/prod; backups verified.
- **Owner:** DevOps Lead.
- **Priority:** P0.
- **Status:** Adopted.

### DR-074 — ClickHouse Cloud for analytics (refinement of DR-034)
- **Date:** 2026-07-10
- **Decision:** ClickHouse Cloud for event analytics. Reaffirms DR-034. Snowflake deferred to Phase 3+.
- **Rationale:** Sub-second queries on billions of events at 10-20% of Snowflake cost. Managed ClickHouse scales automatically. Snowflake justified only at >$50M ARR with complex BI.
- **Evidence Required:** ClickHouse Cloud provisioned; queries <1s on 100M events.
- **Owner:** DevOps Lead + Data Lead.
- **Priority:** P0.
- **Status:** Adopted.

### DR-075 — Multi-tenancy via retailer_id FK + RLS (refinement of DR-008)
- **Date:** 2026-07-10
- **Decision:** Multi-tenancy via `retailer_id` foreign key on every tenant-scoped table + Postgres Row-Level Security (RLS) policies. NOT separate Postgres schemas per tenant (refines DR-008 which originally said schema-per-tenant).
- **Rationale:** Schema-per-tenant becomes operationally painful beyond 50 tenants (migration fan-out, connection pool exhaustion). RLS with `retailer_id` column is simpler and scales to thousands of tenants. Migration is straightforward if we ever need to extract a tenant to a dedicated DB.
- **Evidence Required:** RLS policies on all tenant tables; pen test confirms no cross-tenant access.
- **Owner:** Backend Lead.
- **Priority:** P0.
- **Status:** Adopted. Supersedes DR-008.

### DR-076 — Triton Inference Server as model orchestrator (reaffirms DR-050)
- **Date:** 2026-07-10
- **Decision:** NVIDIA Triton Inference Server for all AI model serving. Reaffirms DR-050.
- **Rationale:** Best-in-class for multi-model pipelines. TensorRT integration. Dynamic batching. Model versioning. Alternatives (BentoML, Ray Serve, vLLM) less fit for vision model pipelines.
- **Evidence Required:** Triton deployed; all models served through it.
- **Owner:** AI Lead.
- **Priority:** P0.
- **Status:** Adopted.

### DR-077 — Terraform for all infrastructure; no manual AWS changes
- **Date:** 2026-07-10
- **Decision:** All AWS infrastructure provisioned via Terraform. No manual console changes allowed in staging or production. Drift detection via `terraform plan` in CI.
- **Rationale:** Manual changes create untracked state, drift, and outages. Terraform provides reproducibility, review, and rollback. Drift detection catches manual changes for correction.
- **Evidence Required:** All infra in Terraform; drift detection CI check; PR required for infra changes.
- **Owner:** DevOps Lead.
- **Priority:** P0.
- **Status:** Adopted.

### DR-078 — Trunk-based development; conventional commits; squash merge
- **Date:** 2026-07-10
- **Decision:** Trunk-based development with short-lived feature branches (<3 days). Conventional Commits format enforced by commitlint. Squash and merge to `main`. PR required.
- **Rationale:** Trunk-based enables continuous deployment. Short branches reduce merge conflicts. Conventional commits enable automated versioning and changelog. Squash merges keep history clean.
- **Evidence Required:** commitlint enforced in CI; branch protection on `main`; PR template used.
- **Owner:** Principal Software Architect.
- **Priority:** P0.
- **Status:** Adopted.

### DR-079 — Test pyramid: 75% unit / 20% integration / 5% E2E
- **Date:** 2026-07-10
- **Decision:** Test pyramid: 75% unit tests (mocked deps), 20% integration tests (testcontainers with real DB), 5% E2E tests (Playwright). Coverage targets: business logic ≥80%, API handlers ≥70%, AI inference ≥60%, SDK ≥70%, infra ≥50%.
- **Rationale:** Pyramid balances speed (unit), confidence (integration), and end-to-end validation (E2E). Inverted pyramid (mostly E2E) is slow and flaky. Mostly unit tests miss integration bugs.
- **Evidence Required:** Coverage reports in CI; tests run in <10 minutes total.
- **Owner:** Principal Software Architect.
- **Priority:** P0.
- **Status:** Adopted.

### DR-080 — Sentry for errors, Datadog for metrics, PagerDuty for alerts
- **Date:** 2026-07-10
- **Decision:** Sentry for error tracking. Datadog for metrics and dashboards. PagerDuty for on-call alerting. Statuspage for public status.
- **Rationale:** Best-in-class for each function. Don't build observability — buy it. Datadog expensive but worth it for unified metrics + logs + traces.
- **Evidence Required:** All three integrated; on-call schedule live; status page public.
- **Owner:** DevOps Lead.
- **Priority:** P0.
- **Status:** Adopted.

### DR-081 — Distroless Docker images for Go services
- **Date:** 2026-07-10
- **Decision:** All Go services use distroless static runtime images. No Alpine, no Debian.
- **Rationale:** Distroless images have zero shell, zero package manager — drastically reduces attack surface. Smaller images (10-20MB). Fewer CVEs. Go statically compiles, so distroless works perfectly.
- **Evidence Required:** All Go services on distroless; image size <30MB; Snyk scan clean.
- **Owner:** DevOps Lead.
- **Priority:** P0.
- **Status:** Adopted.

### DR-082 — golang-migrate for database migrations
- **Date:** 2026-07-10
- **Decision:** Use `golang-migrate` for Postgres schema migrations. Migrations versioned in `migrations/` folder. Forward-only; no auto-rollback.
- **Rationale:** Industry standard for Go + Postgres. Simple (SQL files). CI-enforced (migrations run on deploy). No ORM-based migrations (avoid lock-in to GORM/AutoMigrate).
- **Evidence Required:** Migration files for all schemas; CI runs migrations on staging deploy.
- **Owner:** Backend Lead.
- **Priority:** P0.
- **Status:** Adopted.

### DR-083 — OpenAPI 3.1 spec as single source of truth; auto-generate clients
- **Date:** 2026-07-10
- **Decision:** Single OpenAPI 3.1 spec in `packages/contracts/openapi.yaml`. Auto-generate TypeScript, Go, Python clients via codegen. No hand-written API clients.
- **Rationale:** Single source of truth prevents drift between server and client. Codegen ensures type safety. Changes to spec propagate automatically. Hand-written clients always drift.
- **Evidence Required:** Codegen pipeline in CI; all SDKs use generated clients.
- **Owner:** Principal Software Architect.
- **Priority:** P0.
- **Status:** Adopted.

### DR-084 — AWS Secrets Manager for production secrets; Doppler for dev
- **Date:** 2026-07-10
- **Decision:** Production secrets in AWS Secrets Manager, fetched at runtime by ECS tasks via IAM role. Dev secrets in Doppler, synced to `.env` via `doppler run`. No `.env` files in production. No secrets in Git.
- **Rationale:** Secrets Manager integrates with ECS IAM — no long-lived credentials. Doppler makes local dev ergonomic. Both have audit logs. Git-secrets + pre-commit hooks prevent accidental commits.
- **Evidence Required:** No secrets in Git history (git-secrets scan); all prod secrets in Secrets Manager; audit log accessible.
- **Owner:** DevOps Lead.
- **Priority:** P0.
- **Status:** Adopted.

### DR-085 — 5-milestone roadmap: Foundation → AI MVP → Hardening → Pilot → Scale
- **Date:** 2026-07-10
- **Decision:** Implementation roadmap: M1 Foundation (weeks 1-4), M2 AI Engine MVP (weeks 5-10), M3 Production Hardening (weeks 11-14), M4 iOS SDK + Pilot (weeks 15-20), M5 Enterprise Scale (weeks 21-32). Each milestone has explicit Definition of Done. No skipping.
- **Rationale:** Sequential de-risking. Each milestone has clear deliverables and exit criteria. Allows re-prioritization at milestone boundaries. Aligns with DR-064 AI roadmap.
- **Evidence Required:** Milestone exit criteria met before next milestone begins; documented in `docs/roadmap.md`.
- **Owner:** Principal Software Architect + CTO.
- **Priority:** P0.
- **Status:** Adopted.
