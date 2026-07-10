# Retailer Integration Blueprint v1.0
## Enterprise SDK + API Platform for AI Virtual Try-On

**Document type:** Enterprise integration blueprint (pre-contract reference)
**Author:** Chief Enterprise Solutions Architect
**Date:** 2026-07-10
**Status:** DRAFT — for retailer CTO/VP Eng review
**Mode:** B2B Enterprise SDK (no consumer app)

> **One-sentence value prop:** Drop our SDK into your existing iOS, Android, or Web app. Your customers scan their body once. They try on any garment from your catalog in under 3 seconds. You pay only when a try-on image is successfully generated and viewed.

---

# Table of Contents

1. Executive Summary
2. How a retailer integrates our SDK
3. Complete integration workflow
4. SDK architecture
5. REST API architecture
6. Authentication system
7. Customer identity flow
8. Body scan flow
9. Garment retrieval flow
10. Virtual Try-On generation flow
11. Analytics pipeline
12. Event tracking
13. Webhooks
14. Dashboard capabilities
15. Privacy architecture
16. Security architecture
17. Required retailer data
18. Optional retailer data
19. API endpoints
20. SDK methods
21. Error handling
22. Offline handling
23. Rate limits
24. Billing architecture
25. Usage metering
26. Successful Try-On definition
27. Exactly when billing occurs
28. Enterprise onboarding
29. Developer onboarding
30. Estimated integration effort
31. Team size required
32. Third-party dependencies
33. Cloud architecture
34. Edge architecture
35. Mobile architecture
36. Future API expansion
37. Biggest engineering risks
38. Biggest business risks
39. Recommended MVP
40. Final recommendation

---

# 1. Executive Summary

## What we are

A vertically-focused B2B SDK + API platform that does exactly one thing: **AI Virtual Try-On for apparel retailers.** We are not a marketplace, not a consumer app, not a portfolio of retail-tech features. One feature, done exceptionally well, exposed as a developer-grade SDK and REST API.

## What we are not

- We do not own customer accounts, checkout, loyalty, or payments. The retailer does.
- We do not own the product catalog. The retailer does. We ingest it.
- We do not replace the retailer's mobile app or website. We embed inside it.
- We are not an advertising or recommendation engine. We generate try-on images.

## The model in one paragraph

Retailer installs our SDK (iOS / Android / Web) and provisions API credentials. Retailer's app shows a "Try It On" button on product detail pages. When clicked, the SDK launches the body-scan flow (first time only — ~30 seconds) and then renders the try-on image (~2 seconds server-side). The retailer is billed per successfully-generated and viewed try-on image. No upfront license fee. No per-store pricing. No per-seat SaaS. Pure usage-based, like Stripe or Firebase.

## Why this model wins

| Dimension | Consumer-app model (rejected) | Enterprise SDK model (this blueprint) |
|-----------|-------------------------------|---------------------------------------|
| Customer acquisition cost | High (must acquire each shopper) | Zero (retailer already has the shopper) |
| Identity friction | High (shopper creates account with us) | Zero (retailer's existing account) |
| Catalog access | Negotiate per brand | Retailer provides their own catalog |
| Checkout | We build or integrate | Retailer's existing checkout |
| Distribution | App store competition | Inside retailer's installed base |
| Revenue per integration | $50-200K/brand/yr | $50K-2M/retailer/yr (usage-scaled) |
| Time to revenue | 12-18 months | 8-12 weeks per retailer |

## Recommended pricing (refined)

- **Per Successful Try-On:** $0.15 (default), tiered down to $0.08 at high volume
- **Monthly minimum commit:** $2,000 (waived for first 90 days of pilot)
- **Body scan:** Free (we eat this cost — it's the funnel)
- **Garment digitization:** $25/SKU one-time, $0 for first 500 SKUs per retailer
- **Dashboard, webhooks, analytics:** Included

**Why the minimum commit exists:** pure pay-per-success creates adverse selection where we bear all failure risk. The minimum commit is the retailer's "skin in the game." Stripe has processing minimums; Firebase has spend alerts. This is industry-standard and protects us.

## Bottom line for the retailer

A 4-6 week integration by 2 engineers. No upfront cost. Pricing that scales with usage. A feature their customers have been asking for. Analytics that prove ROI. Exit any time (data portability guaranteed).

## Bottom line for us

One product to build. One SDK to maintain. Three platforms (iOS/Android/Web). Per-try-on unit economics that work at $0.05 cost / $0.15 price = 67% gross margin. Path to $100M ARR through 200-500 retailer integrations averaging $200K-500K/yr each.

---

# 2. How a Retailer Integrates Our SDK — Start to Finish

## The 6-step journey

```
┌─────────────────────────────────────────────────────────────────────┐
│  STEP 1: COMMERCIAL                                                 │
│  Retailer signs MSA + DPA. Provisioning ticket created.             │
│  Owner: Retailer CIO + Our Head of Sales                            │
│  Duration: 2-4 weeks (large retailers) / 1 week (mid-market)        │
├─────────────────────────────────────────────────────────────────────┤
│  STEP 2: ONBOARDING                                                 │
│  Retailer gets: tenant ID, API keys (sandbox + prod), dashboard     │
│  access, SDK credentials, Slack Connect channel.                    │
│  Owner: Our Solutions Engineer + Retailer Tech Lead                 │
│  Duration: 2-3 days                                                  │
├─────────────────────────────────────────────────────────────────────┤
│  STEP 3: CATALOG INGESTION                                          │
│  Retailer sends us their catalog via:                               │
│    - Product feed (CSV/JSON) OR                                     │
│    - API push from their PIM OR                                     │
│    - Shopify/Salesforce connector                                   │
│  We digitize each SKU into try-on-ready format (2D representation). │
│  Owner: Our Digitization Pipeline + Retailer Catalog Team           │
│  Duration: 1-3 weeks depending on catalog size (target: 500 SKUs/wk)│
├─────────────────────────────────────────────────────────────────────┤
│  STEP 4: SDK INSTALLATION                                           │
│  Retailer's mobile team adds SDK via SwiftPM/Gradle/npm.            │
│  Web team adds <script> tag or npm package.                         │
│  Configures: tenant ID, API key, theme, locale.                     │
│  Owner: Retailer Mobile Lead + Retailer Web Lead                    │
│  Duration: 1-2 days                                                  │
├─────────────────────────────────────────────────────────────────────┤
│  STEP 5: INTEGRATION                                                │
│  Retailer wires "Try It On" button on PDP (product detail page).    │
│  SDK handles: scan flow, try-on render, result display, events.     │
│  Retailer handles: button placement, theming, A/B test.             │
│  Server-side: retailer receives webhooks (try-on events,            │
│  purchase attribution).                                             │
│  Owner: Retailer Mobile Eng (2 engineers) + Retailer Backend (1)    │
│  Duration: 3-5 weeks                                                 │
├─────────────────────────────────────────────────────────────────────┤
│  STEP 6: LAUNCH + OPTIMIZE                                          │
│  Sandbox QA → staged rollout → production.                          │
│  Analytics dashboard live.                                          │
│  Weekly optimization review (button placement, scan completion).    │
│  Owner: Joint — Our CSM + Retailer Product                          │
│  Duration: Ongoing                                                   │
└─────────────────────────────────────────────────────────────────────┘
```

## Total wall-clock time

- **Mid-market retailer (10-100 stores):** 6-8 weeks from signed MSA to production launch
- **Enterprise retailer (500+ stores):** 10-14 weeks (longer catalog ingestion + legal review)
- **Direct-to-consumer brand (Shopify-class):** 4-6 weeks (simpler catalog, faster legal)

---

# 3. Complete Integration Workflow

## End-to-end swimlane

```
RETAILER APP                RETAILER BACKEND              OUR PLATFORM
(shopper device)            (retailer cloud)              (our cloud)

[Shopper on PDP]
clicks "Try It On"
     │
     ▼
SDK checks: does shopper
have a body profile?
     │
     ├── NO ──► SDK launches Body Scan flow
     │          (camera UI, on-device consent,
     │           ~30s scan, mesh → server)
     │                                          ◄─── POST /v1/body_profiles
     │                                          (with retailer-scoped token) ──┐
     │                                                                              │
     │                                          Body profile created             │
     │                                          (encrypted, consent logged)       │
     │                                          ◄─── 200 OK + profile_id  ───────┘
     │
     ├── YES ──► SDK fetches profile_id from local storage
     │
     ▼
SDK requests try-on
     │
     ├── POST /v1/tryons ──────────────────────────────────────┐
     │   {profile_id, garment_sku, retailer_id, view_options}   │
     │                                                          ▼
     │                                              Try-on job queued
     │                                              (warm GPU pool picks up)
     │                                              ~2s inference
     │                                                          │
     │                                              POST /v1/tryons/{id}
     │                                              (poll) OR webhook fires  ─┐
     │                                                                          │
     │ ◄── 200 OK {tryon_id, status, image_url, expires_at} ──────────────────┘
     │
     ▼
SDK renders try-on image
Shopper swipes between views
     │
     ├── POST /v1/events ──► {type: "tryon_viewed", tryon_id, ...}  ──► Event log
     │                                                                   (billing trigger)
     │
     ▼
Shopper adds to cart (retailer's existing flow)
     │
     ├── Retailer checkout happens normally
     │
     ▼
Purchase event
     │
     ├── Retailer backend fires webhook to us:
     │   POST /v1/attribution
     │   {tryon_id, order_id, order_total, sku}
     │                                                          ▼
     │                                              Attribution recorded
     │                                              (drives ROI dashboard)
     │
     ▼
Weekly: retailer views analytics dashboard
        (try-on conversion, top SKUs, return-rate delta)
```

## Critical design principle

**The retailer's existing flows are untouched.** We add exactly two surfaces to their app:
1. A "Try It On" button on the PDP
2. A try-on result viewer (modal or full-screen)

Everything else — login, cart, checkout, loyalty, returns — is the retailer's. We are a feature, not a platform replacement.

---

# 4. SDK Architecture

## Platform coverage

| Platform | Package Manager | Min Version | Distribution |
|----------|----------------|-------------|--------------|
| iOS | Swift Package Manager | iOS 15+ (LiDAR requires iPhone 12 Pro+) | Binary framework (XCFramework) |
| Android | Gradle (Maven) | Android 10+ (API 29), ARCore 1.40+ | AAR via Maven Central |
| Web | npm + CDN | Modern browsers (Chrome 100+, Safari 15+, Firefox 100+) | ESM module + IIFE bundle |
| React Native | npm | RN 0.71+ | Wraps native iOS/Android SDKs |
| Flutter | pub.dev | Flutter 3.10+ | Platform channel wrappers |

## SDK module structure

```
TryOnSDK/
├── Core/
│   ├── Configuration        // tenant ID, API key, environment
│   ├── Logger               // structured logging, opt-in
│   ├── Networking           // HTTP client, retry, circuit breaker
│   ├── Storage              // encrypted local cache (Keychain/Keystore/IndexedDB)
│   └── Telemetry            // opt-in usage analytics
│
├── Identity/
│   ├── SessionManager       // manages retailer-issued tokens
│   ├── ConsentStore         // per-scan consent records
│   └── ProfileCache         // body profile ID cache
│
├── BodyScan/
│   ├── ScanController       // orchestrates scan flow
│   ├── DepthCapture         // ARKit (iOS) / ARCore (Android) / WebXR
│   ├── MeshBuilder          // on-device mesh construction
│   ├── QualityChecker       // real-time scan quality feedback
│   └── Uploader             // chunked upload to platform
│
├── TryOn/
│   ├── TryOnClient          // submits try-on requests
│   ├── ResultCache          // caches recent try-ons (TTL: 24h)
│   ├── Viewer               // UI component for displaying result
│   └── ShareSheet           // optional: shopper shares result
│
├── UI/
│   ├── Theme                // colors, fonts, corner radius (retailer-configurable)
│   ├── ScanView             // body scan camera UI
│   ├── TryOnView            // try-on result viewer
│   ├── LoadingStates        // skeleton loaders
│   └── ErrorViews           // branded error states
│
└── Analytics/
    ├── EventTracker         // fires events to platform
    └── FunnelRecorder       // local funnel state for retry
```

## SDK size budget

| Platform | Initial download | After first body scan | Notes |
|----------|-----------------|----------------------|-------|
| iOS | 8 MB | 12 MB | ML model downloaded lazily on first scan |
| Android | 6 MB | 10 MB | Same |
| Web | 200 KB (initial) | 2 MB (lazy) | Code-split; ML model loaded only when scan initiated |

These sizes matter — retailers will not accept a 50 MB SDK that bloats their app. Lazy loading is non-negotiable.

## Threading model

- **iOS:** Body scan on background queue, viewer on main thread, networking on dedicated session
- **Android:** Body scan on camera thread, viewer on UI thread, networking via OkHttp
- **Web:** Body scan in Web Worker, viewer on main thread, networking via fetch + service worker

## Memory budget

- Peak RAM during body scan: <150 MB (otherwise iOS jetsam kills us on lower devices)
- Steady-state RAM after scan: <30 MB
- Peak GPU memory during render: <50 MB

---

# 5. REST API Architecture

## Design principles

1. **RESTful + JSON.** No GraphQL for v1 (complexity, caching). No gRPC for external API (interoperability). We may add gRPC for internal.
2. **Versioned.** URL-based versioning (`/v1/`). Breaking changes = new version. Non-breaking = additive.
3. **Idempotent where it matters.** POST /tryons, POST /body_profiles, POST /events all accept `Idempotency-Key` header.
4. **Async by default for compute.** Try-on generation is async (queue → poll or webhook). Sync endpoints only for fast reads.
5. **Consistent error model.** RFC 7807 Problem Details for every error response.

## Request/response envelope

```json
// Success
{
  "data": { ... },
  "meta": { "request_id": "req_abc123", "version": "v1" }
}

// Error (RFC 7807)
{
  "type": "https://docs.tryonsdk.com/errors/tryon_failed",
  "title": "Try-on generation failed",
  "status": 422,
  "detail": "Garment SKU not digitized",
  "instance": "req_abc123",
  "errors": [
    { "code": "garment_not_digitized", "field": "garment_sku", "value": "SKU-12345" }
  ]
}
```

## Endpoint categories

| Category | Sync/Async | Auth | Notes |
|----------|-----------|------|-------|
| Catalog | Sync | Server-to-server | Retailer pushes SKUs to us |
| Body Profiles | Async (creation), Sync (read) | SDK token + server-to-server | Contains biometric data |
| Try-Ons | Async | SDK token | Webhook + poll |
| Events | Sync (fire-and-forget) | SDK token | High volume |
| Analytics | Sync | Server-to-server | Aggregated only |
| Webhooks | Outbound only | Signed | We call retailer |
| Billing | Sync | Server-to-server | Usage + invoices |

Full endpoint list in Section 19.

## Pagination

Cursor-based, never offset. `?cursor=xyz&limit=50`. Default limit 50, max 200.

## Rate limit headers

Every response includes:
```
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 999
X-RateLimit-Reset: 1690000000
X-RateLimit-Policy: 1000-per-minute
```

## Compatibility promise

- We will not break a `/v1/` endpoint for at least 24 months after GA.
- Deprecation: 6-month minimum notice via email + dashboard + `Sunset` header.
- Field additions are non-breaking. Field removals are breaking.

---

# 6. Authentication System

## Three-layer auth model

```
┌─────────────────────────────────────────────────────────────────┐
│ LAYER 1: SERVER-TO-SERVER (retailer backend ↔ our platform)    │
│ Auth: OAuth 2.0 Client Credentials Grant                       │
│ Token: JWT, 1h TTL, scoped to tenant                            │
│ Used for: catalog push, analytics read, billing read,          │
│           webhook signature verification, attribution push     │
│ Secrets: RSA key pair (retailer holds private key)             │
└─────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────┐
│ LAYER 2: SDK-TO-PLATFORM (shopper device ↔ our platform)       │
│ Auth: Short-lived bearer token issued by retailer backend      │
│ Token: JWT, 1h TTL, scoped to (tenant_id, shopper_id)          │
│ Used for: body scan upload, try-on requests, event tracking    │
│ Secrets: API key embedded in SDK (low privilege, rate-limited) │
└─────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────┐
│ LAYER 3: BIOMETRIC CONSENT (per body scan)                      │
│ Auth: Explicit user consent captured in-app, signed and logged │
│ Token: Consent receipt ID returned with profile creation       │
│ Used for: Audit trail, GDPR/BIPA/CCPA compliance               │
└─────────────────────────────────────────────────────────────────┘
```

## Token issuance flow (Layer 2)

```
1. Shopper opens retailer app, logged in via retailer's auth
2. Retailer app calls retailer backend: "give me a try-on token for user X"
3. Retailer backend calls our token endpoint:
   POST /v1/tokens
   Authorization: Bearer <server-to-server token>
   { "shopper_id": "retailer_user_123", "scopes": ["body_scan", "tryon"] }
4. Our platform returns:
   { "access_token": "eyJ...", "expires_in": 3600, "shopper_token_id": "st_abc" }
5. Retailer backend passes token to SDK
6. SDK uses token for all subsequent calls until expiry
```

## Why this design

- Retailer never shares their customer's password with us
- We never see retailer's session cookies
- Tokens are scoped — body-scan tokens can't read billing data
- Retailer can revoke any shopper's access instantly by revoking the server-to-server token's permission to mint new shopper tokens
- Tokens are short-lived — even if leaked, blast radius is small

## What we explicitly do NOT do

- We do NOT issue our own user accounts. The shopper is the retailer's customer, not ours.
- We do NOT store passwords.
- We do NOT use API keys for SDK calls (they leak). API keys are server-to-server only.
- We do NOT use long-lived tokens for shoppers. 1-hour max.

---

# 7. Customer Identity Flow

## The principle: retailer owns identity, we hold a pointer

```
┌──────────────────────┐                    ┌──────────────────────┐
│  RETAILER            │                    │  OUR PLATFORM        │
│                      │                    │                      │
│  user_id: "u_12345"  │◄──── scoped ────►  │  shopper_ref:        │
│  email: a@b.com      │     token          │    "retailer_X:u_12345"
│  loyalty_tier: gold  │                    │  body_profile_id:    │
│  purchase_history    │                    │    "bp_xyz789"       │
│                      │                    │  (no PII stored)     │
└──────────────────────┘                    └──────────────────────┘
```

## What we store about a shopper

| Field | Stored? | Why |
|-------|---------|-----|
| Retailer's user ID | Yes (as opaque string) | Cross-reference for webhooks |
| Email | **No** | Not needed; retailer has it |
| Name | **No** | Not needed |
| Body profile ID | Yes | Required to generate try-ons |
| Body measurements | Yes (encrypted) | Required for fit; customer-held key option |
| Body scan raw data | **No** (deleted after profile creation) | Minimization |
| Consent records | Yes | Legal requirement |
| Try-on history | Yes (90 days) | For shopper's own "recently tried on" UI |
| Purchase attribution | Yes (anonymized) | For ROI dashboard |

## Identity handoff flow

```
1. Shopper logs into retailer app (retailer's existing auth)
2. Shopper taps "Try It On" on a PDP
3. Retailer app fetches scoped token from retailer backend
4. Retailer backend calls our /v1/tokens endpoint with shopper_id
5. SDK receives token, makes try-on request with token
6. We link try-on to shopper via shopper_token_id (not retailer's user_id directly)
7. On purchase, retailer sends attribution webhook with order_id + tryon_id
8. We reconcile to compute ROI per shopper (anonymized)
```

## Multi-retailer shopper scenario

A shopper may use our try-on in Retailer A's app AND Retailer B's app. **We do NOT merge these profiles.** Each retailer gets a separate body_profile_id. Reasons:
- Privacy: shopper may not want Retailer B to know they scanned with Retailer A
- Compliance: cross-retailer profile merging requires explicit consent under GDPR
- Business: retailers are paying us; they would not appreciate us sharing their customer's body data with competitors

**Phase 2 option:** shopper-initiated "port my body profile" flow (consent-gated, opt-in). This unlocks the network effect without violating privacy.

---

# 8. Body Scan Flow

## Design goals

1. **Sub-30-second scan time** (the Walmart/Zeekit failure was 2+ minutes — killed engagement)
2. **On-device consent capture** before any data leaves the phone
3. **Quality feedback during scan** (not after — too late)
4. **Resumable upload** (cellular drops mid-scan should not lose work)
5. **Cross-device consistency** (iPhone Pro LiDAR is the gold path; Android falls back to RGB-only 2-photo approach)

## Scan sequence (iOS Pro, gold path)

```
T+0s    Shopper taps "Try It On" → "Create my body profile"
T+1s    Consent modal: "We'll capture your body shape. Your face is not
        captured. Data is encrypted. Delete anytime."
        [I Consent] [Cancel]
T+3s    Camera opens, ARKit body tracking initialized
T+5s    On-screen guide: "Stand 2m away, face the camera, arms slightly
        away from body"
T+7s    Shopper positions; auto-detect → "Hold still..."
T+8s    Scan begins. ARKit LiDAR captures depth frames at 30fps.
        Shopper slowly rotates 360° (guided by on-screen arrow).
T+25s   Scan complete. On-device mesh construction begins.
T+27s   Mesh quality check (vertex count, coverage, symmetry).
        If fails: "Let's try again" with specific feedback.
T+30s   Mesh uploaded to platform (chunked, resumable, encrypted).
T+32s   Platform fits SMPL-X parametric model to mesh.
T+35s   Body profile created. profile_id returned.
T+36s   SDK caches profile_id. Shopper sees "Profile ready!" → try-on starts.
```

## Scan sequence (Android, fallback path)

For Android devices without depth-sensing:
```
T+0s    Same consent flow
T+5s    Camera opens, ARCore body tracking (where supported)
        OR RGB-only 2-photo approach (front + side, 3DLOOK-style)
T+10s   Photo 1: front view (auto-capture when pose detected)
T+15s   Photo 2: side view (auto-capture)
T+20s   Photos uploaded. Server-side mesh inference (PIFuHD-class model).
T+35s   Profile ready.
```

## Quality gates

The SDK refuses to submit a scan that fails quality checks. This protects unit economics (we don't pay GPU cost to process garbage).

| Check | Threshold | Action on fail |
|-------|-----------|----------------|
| Mesh vertex count | >5,000 | Re-scan |
| Body coverage | >85% of body | Re-scan with guidance |
| Symmetry score | >0.8 | Re-scan |
| Loose clothing detection | Flagged | "Wear form-fitting clothing" prompt |
| Motion blur | <threshold | Re-scan |
| Lighting | >50 lux | "Move to brighter area" prompt |

## Rescan policy

- Profiles expire after 12 months (body shapes change; stale profiles produce bad try-ons)
- Shopper can rescan anytime
- Shopper can delete profile anytime (deletes within 72h SLA, immediate from their view)
- Retailer cannot delete shopper profiles (only the shopper can)

## Privacy commitments

- Raw scan data (mesh, depth frames) is deleted within 24 hours of profile creation
- Only the parametric body model (SMPL-X parameters) is retained
- No face data is captured (face region is masked out in the SDK before upload)
- No audio is captured
- Geolocation is not captured

---

# 9. Garment Retrieval Flow

## The model: retailer pushes catalog, we digitize, we serve

```
RETAILER PIM/SHOPIFY            OUR DIGITIZATION PIPELINE         OUR CATALOG SERVICE
        │                                │                                │
        │  POST /v1/catalog/skus         │                                │
        ├───────────────────────────────►│                                │
        │  {sku, name, category,         │                                │
        │   image_urls[], size_chart,    │                                │
        │   fabric, color, gender}       │                                │
        │                                │                                │
        │                                │  Ingest image                  │
        │                                │  Run segmentation              │
        │                                │  Extract garment attributes   │
        │                                │  Generate try-on representation│
        │                                │  (front, back, mask, attrs)   │
        │                                │  QC pass/fail                  │
        │                                ├───────────────────────────────►│
        │                                │  status: ready                 │
        │  GET /v1/catalog/skus/{sku}    │                                │
        │◄────────────────────────────────────────────────────────────────┤
        │  {sku, status: ready,          │                                │
        │   digitized_at, quality_score} │                                │
```

## Catalog ingestion modes

| Mode | How it works | Best for |
|------|-------------|----------|
| **Push API** | Retailer pushes SKUs as they're added/updated | Custom PIM, real-time sync |
| **Batch feed** | Nightly CSV/JSON feed via SFTP or signed URL | Legacy systems |
| **Shopify connector** | OAuth to retailer's Shopify, we pull | Shopify retailers |
| **Salesforce Commerce connector** | OAuth to Salesforce Commerce Cloud | Enterprise retailers |
| **Manual upload** | Dashboard upload of CSV | Small catalogs (<100 SKUs) |

## Digitization SLA

| Catalog size | Digitization time | Notes |
|-------------|-------------------|-------|
| <100 SKUs | 24 hours | Manual QC on each |
| 100-1,000 SKUs | 3-5 business days | Auto + sampled QC |
| 1,000-10,000 SKUs | 2-3 weeks | Auto + batch QC |
| 10,000+ SKUs | Custom | Staged rollout |

## Per-SKU output

After digitization, each SKU has:

```json
{
  "sku": "RETAILER_SKU_12345",
  "status": "ready",
  "quality_score": 0.92,
  "digitized_at": "2026-07-10T12:00:00Z",
  "representation": {
    "front_image_url": "https://cdn.tryonsdk.com/...",
    "back_image_url": "https://cdn.tryonsdk.com/...",
    "segmentation_mask_url": "https://cdn.tryonsdk.com/...",
    "category": "dress",
    "attributes": {
      "neckline": "v_neck",
      "sleeve": "short",
      "length": "knee",
      "fabric_category": "woven",
      "pattern": "solid"
    }
  },
  "tryon_support": {
    "views": ["front"],
    "compatible_categories": ["women_dress"]
  }
}
```

## Garment-not-ready handling

If a shopper taps "Try It On" on a SKU that isn't digitized yet:
1. SDK checks status via `GET /v1/catalog/skus/{sku}`
2. If `status != ready`, SDK shows: "Try-on coming soon for this item" + fires `tryon_unavailable` event
3. Retailer's dashboard flags the SKU for expedited digitization

---

# 10. Virtual Try-On Generation Flow

## End-to-end

```
1. Shopper taps "Try It On" on PDP
2. SDK determines body profile is available (or triggers scan per Section 8)
3. SDK calls: POST /v1/tryons
   {
     "body_profile_id": "bp_xyz789",
     "garment_sku": "RETAILER_SKU_12345",
     "view": "front",
     "size": "M",          // optional; default = recommended size from profile
     "shopper_token": "eyJ..."
   }
4. Platform validates:
   - Shopper token valid & scoped to body_profile_id
   - Garment SKU is digitized and ready
   - Shopper token's retailer_id matches garment's retailer_id
5. Platform returns:
   200 OK
   {
     "tryon_id": "tryon_abc123",
     "status": "pending",
     "estimated_wait_seconds": 2,
     "poll_url": "/v1/tryons/tryon_abc123",
     "webhook_url": "https://api.retailer.com/tryon-webhook"
       (optional; retailer may register global webhook instead)
   }
6. Try-on job enters queue
7. Warm GPU instance picks up job (avg queue time: 200ms)
8. Model inference: ~1.5s on A10 GPU (CatVTON fine-tuned)
9. Post-processing: background removal, color correction (~200ms)
10. Image uploaded to CDN (Cloudflare R2 + CloudFront)
11. Status updated to "succeeded"
12. Webhook fires to retailer (if registered)
13. SDK polls /v1/tryons/{id} (every 500ms, max 10 polls)
    OR receives push notification via WebSocket (premium tier)
14. SDK receives image URL, displays result
15. Shopper views image → SDK fires "tryon_viewed" event
    (THIS is the billing trigger per Section 26)
```

## Try-on result object

```json
{
  "tryon_id": "tryon_abc123",
  "status": "succeeded",
  "body_profile_id": "bp_xyz789",
  "garment_sku": "RETAILER_SKU_12345",
  "size": "M",
  "image_url": "https://cdn.tryonsdk.com/tryons/abc123.webp",
  "image_url_expires_at": "2026-07-11T12:00:00Z",
  "thumbnail_url": "https://cdn.tryonsdk.com/tryons/abc123_thumb.webp",
  "metadata": {
    "model_version": "viton-v2.3",
    "quality_score": 0.89,
    "render_time_ms": 1820
  },
  "billing": {
    "billed": false,
    "will_bill_on": "view"
  }
}
```

## Image format and CDN

- Format: WebP (40% smaller than JPEG at equivalent quality)
- Resolution: 1024×1536 (2:3 portrait, matches mobile screen)
- CDN: Cloudflare R2 (zero egress fees) + CloudFront (global PoPs)
- Signed URLs with 24-hour TTL
- Retailer can proxy through their own CDN if needed

## Try-on result caching

To avoid re-billing for repeat views:
- Same (body_profile_id, garment_sku, size, view) within 24 hours = cached result, no new try-on generated
- Retailer is NOT billed for cached results served again
- This is fair: we're not doing new compute, we're not charging

---

# 11. Analytics Pipeline

## What we measure

### Funnel events (per shopper session)

```
tryon_button_shown      → "Try It On" button rendered on PDP
tryon_button_tapped     → Shopper tapped the button
scan_started            → Body scan flow began
scan_completed          → Scan finished successfully
scan_abandoned          → Scan flow exited before completion
tryon_requested         → Try-on API call made
tryon_succeeded         → Image generated successfully
tryon_failed            → Generation failed (any reason)
tryon_viewed            → Shopper viewed the result (BILLING TRIGGER)
tryon_swiped            → Shopper swiped to additional views
tryon_shared            → Shopper shared result (if enabled)
add_to_cart_after_tryon → Shopper added to cart within 5 min of try-on
purchase_after_tryon    → Shopper purchased within 24h of try-on (via attribution webhook)
```

### Aggregate metrics (retailer dashboard)

- Try-on adoption rate (tryon_button_tapped / tryon_button_shown)
- Scan completion rate (scan_completed / scan_started)
- Try-on success rate (tryon_succeeded / tryon_requested)
- Try-on view rate (tryon_viewed / tryon_succeeded)
- Try-on to cart rate (add_to_cart_after_tryon / tryon_viewed)
- Try-on to purchase rate (purchase_after_tryon / tryon_viewed)
- Return rate delta (returns on try-on purchases vs. non-try-on purchases)
- Top SKUs by try-on count
- Bottom SKUs by try-on failure rate (digitization quality signal)

## Pipeline architecture

```
SDK events ──► Ingest API ──► Kafka ──► Stream processor ──► ClickHouse
                  │                          │                  │
                  │                          │                  ├─► Real-time dashboard
                  │                          │                  ├─► Daily aggregates
                  │                          │                  └─► Retailer export API
                  │                          ▼
                  │                    Event validator
                  │                    (drop malformed)
                  │
                  └──► Idempotency cache (Redis, 24h TTL)
                       (dedupes retries from SDK)
```

## Tech choices

- **Kafka:** durable event stream, replayable for backfill
- **ClickHouse:** sub-second queries on billions of events; far cheaper than Snowflake for this workload
- **Redis:** idempotency dedup; not for analytics
- **No Snowflake/BigQuery for v1:** overkill cost; ClickHouse handles 95% of queries

## Data freshness

- Real-time dashboard: <30 second lag
- Daily aggregates: refreshed hourly
- Weekly executive summary: emailed Mondays 9am retailer local time

---

# 12. Event Tracking

## Event schema

All events share a common envelope:

```json
{
  "event_id": "evt_uuid",          // SDK-generated, idempotent
  "event_type": "tryon_viewed",
  "timestamp": "2026-07-10T12:34:56.789Z",
  "shopper_token_id": "st_abc",
  "retailer_id": "retailer_123",
  "session_id": "sess_xyz",
  "tryon_id": "tryon_abc123",      // when applicable
  "garment_sku": "SKU_12345",      // when applicable
  "body_profile_id": "bp_xyz789",  // when applicable
  "device": {
    "platform": "ios",
    "os_version": "17.4.1",
    "app_version": "1.2.3",
    "device_model": "iPhone 14 Pro"
  },
  "locale": "en-US",
  "custom_attributes": {}          // retailer-defined (opt-in)
}
```

## Event delivery guarantees

- **At-least-once delivery** (events may arrive twice; never zero times)
- **Ordering:** best-effort within a session; not guaranteed across sessions
- **Retry:** SDK retries failed events for 24 hours with exponential backoff
- **Offline:** events queued locally (encrypted), uploaded when connectivity returns

## Event batching

SDK batches events (max 50 events or 5 seconds, whichever first) to reduce API calls. Retailers concerned about real-time analytics can configure `flush_interval: 1s`.

## What retailers can send us

Retailers may attach custom attributes to events via `custom_attributes`. This is opt-in and scoped to non-PII fields (e.g., `loyalty_tier`, `acquisition_channel`). We reject custom attributes that look like PII (email, phone, name) and warn the retailer.

---

# 13. Webhooks

## Why webhooks matter

Webhooks are how we tell the retailer about async events: try-on completed, try-on failed, body profile created, billing threshold reached, catalog digitization complete.

## Webhook events

| Event | When fired | Payload |
|-------|-----------|---------|
| `body_profile.created` | New body profile successfully created | profile_id, retailer_id, shopper_ref |
| `tryon.succeeded` | Try-on image generated | tryon_id, sku, image_url, profile_id |
| `tryon.failed` | Try-on generation failed | tryon_id, sku, error_code |
| `tryon.viewed` | Shopper viewed try-on (billing trigger) | tryon_id, sku, billed_amount |
| `catalog.digitized` | SKU digitization complete | sku, quality_score |
| `catalog.failed` | SKU digitization failed | sku, error_code |
| `billing.threshold_reached` | Usage hits 80% of monthly commit | retailer_id, current_usage, commit_amount |
| `attribution.purchase` | Retailer sent us purchase attribution | (inbound, not outbound — covered Section 10) |

## Webhook delivery

```
Our platform ──► HTTPS POST ──► Retailer's webhook URL
                                 (must be HTTPS, must respond 2xx within 10s)
```

## Signing

Every webhook includes:
```
TryOnSDK-Signature: t=1690000000,v1=abc123def456...
TryOnSDK-Event: tryon.succeeded
TryOnSDK-Delivery: whdel_uuid
```

Signature = HMAC-SHA256 of (`t` + `.` + raw_body) using retailer's webhook secret. Retailer MUST verify signature before processing.

## Retry policy

- Retailer must respond 2xx within 10 seconds
- On non-2xx or timeout: retry at 1m, 5m, 30m, 2h, 6h, 24h (6 attempts total)
- After 6 failures: webhook disabled; retailer notified via dashboard + email
- Webhook deliveries are idempotent — retailer must handle duplicates (use `TryOnSDK-Delivery` ID)

## Webhook management

- Retailer registers webhook URL via dashboard or API
- Multiple URLs supported (e.g., dev / staging / prod)
- Per-event subscription (retailer can opt into only `tryon.viewed` and `billing.threshold_reached`)
- Test events via dashboard "Send test webhook" button

---

# 14. Dashboard Capabilities

## What the retailer sees

### Overview tab
- This month: try-ons generated, try-ons viewed, billable amount
- Top 5 SKUs by try-on count
- Conversion funnel (button → scan → try-on → view → cart → purchase)
- Return rate delta (try-on vs. non-try-on purchases)

### Catalog tab
- Digitization status of every SKU
- Bulk upload via CSV
- Per-SKU quality score and failure reasons
- "Re-digitize" button for low-quality SKUs

### Performance tab
- Try-on latency p50/p95/p99
- Try-on success rate over time
- Failure breakdown by error code

### Shoppers tab (anonymized aggregate only)
- Total unique shoppers with body profiles
- Scan completion rate
- Repeat try-on rate
- NO individual shopper PII visible

### Billing tab
- Current month usage
- Per-try-on breakdown (date, SKU, billed amount)
- Historical invoices (downloadable)
- Forecasted month-end bill
- Cost center tags (if retailer uses them)

### Settings tab
- API keys (create, rotate, revoke)
- Webhook configuration
- Team members (RBAC: admin, developer, billing, read-only)
- SDK configuration (theme, locale, feature flags)
- Data export (GDPR/CCPA DSAR fulfillment)

### Developer tab
- API logs (last 7 days, searchable)
- Webhook delivery logs (last 30 days, with retry history)
- Sandbox environment toggle
- SDK version compatibility matrix

## Tech for the dashboard

- Frontend: React + Vite + shadcn/ui (fast to build, easy to maintain)
- Backend: same REST API the retailer's backend uses (we dogfood)
- Auth: SSO via SAML 2.0 (enterprise retailers require this) + email/password fallback
- Hosting: Cloudflare Pages + Workers (cheap, fast, global)

## RBAC roles

| Role | Capabilities |
|------|-------------|
| Admin | Everything |
| Developer | API keys, webhooks, logs, sandbox. No billing. |
| Billing | Invoices, usage, forecast. No API keys. |
| Read-only | View everything, change nothing. |

---

# 15. Privacy Architecture

## Privacy principles

1. **Minimization:** We collect only what's needed to generate try-ons
2. **Purpose limitation:** Body data used only for try-on; never for advertising, never sold
3. **Retention limits:** Raw scans deleted within 24h; body profiles retained per shopper's choice (default 12 months)
4. **Customer control:** Shopper can view, export, delete their data anytime
5. **Auditability:** Every access to body profile data is logged

## Data classification

| Data | Classification | Retention | Encryption |
|------|---------------|-----------|------------|
| Raw body scan (mesh/depth) | Biometric (high) | 24h then deleted | AES-256 at rest, TLS 1.3 in transit |
| Body profile (SMPL-X params) | Biometric (high) | Shopper-controlled (default 12mo) | AES-256 at rest, KMS-managed key |
| Body measurements | Biometric (high) | Same as profile | Same |
| Try-on images | Personal (medium) | 90 days | AES-256 at rest |
| Event logs | Personal (medium) | 13 months | AES-256 at rest |
| Consent records | Legal (high) | 7 years (statute of limitations) | AES-256 at rest, WORM storage |
| Retailer's shopper ID | Identifier (low) | Same as profile | Same |
| Retailer's email/name | **Not stored** | N/A | N/A |

## Encryption

- **At rest:** AES-256 via AWS KMS customer-managed keys. One key per retailer.
- **In transit:** TLS 1.3 mandatory; TLS 1.2 deprecated.
- **Per-shopper encryption option (Phase 2):** Shopper-held key via WebAuthn / Secure Enclave. Platform cannot read body profile without shopper's device present. Zero-knowledge try-on. (Research-grade; deferred.)

## Consent flow

```
1. First time shopper taps "Try It On"
2. SDK shows consent modal:
   "We'll create a digital body profile to show you how clothes fit.
    - Your face is NOT captured
    - Your body shape is encrypted
    - You can delete your profile anytime
    - [Retailer name] and [our company] will use this to generate try-on images
    - We won't use this for anything else

    [Manage preferences] [I consent] [Cancel]"
3. Consent record (signed, timestamped, versioned) stored
4. Subsequent scans: brief reminder, not full re-consent (unless policy changes)
5. Shopper can revoke consent → triggers profile deletion within 72h
```

## GDPR / CCPA / BIPA compliance

- **Right to access:** Shopper requests via retailer; retailer forwards to us; we export within 30 days
- **Right to deletion:** Shopper requests via retailer; we delete within 72h, return confirmation
- **Right to portability:** Shopper can export body profile as standard SMPL-X format
- **BIPA:** Per-scan written consent (the modal); retention only with re-consent annually
- **CCPA:** "Do not sell" is moot — we don't sell data. "Limit use" honored.

## Cross-border data flow

- EU shoppers: data stays in eu-west-1 (Ireland)
- US shoppers: data stays in us-east-1 (Virginia)
- India shoppers (Phase 2+): data stays in ap-south-1 (Mumbai) per DPDP Act
- No cross-region replication of biometric data. Analytics aggregated region-locally.

---

# 16. Security Architecture

## Threat model

| Threat | Mitigation |
|--------|-----------|
| API key leak from retailer backend | Keys are server-side only; rotate via dashboard; alert on anomalous usage |
| SDK token theft from device | 1-hour TTL; scoped; can be revoked by retailer |
| Body profile data breach | KMS-encrypted at rest; row-level encryption; no bulk export endpoint |
| Try-on image URL leak | Signed URLs with 24h TTL; referrer check; rate-limited |
| Malicious retailer employee accessing shopper data | Per-retailer RBAC; audit log; retailer admin cannot view individual body profiles (only aggregate) |
| DDoS on ingestion | Cloudflare WAF + rate limiting; per-IP and per-tenant limits |
| Model exfiltration | Model weights never leave GPU instances; inference API only returns image |
| Supply chain attack on SDK | Signed binaries; SLSA Level 3 build provenance; SBOM published |
| Webhook spoofing | HMAC signature verification; retailer must verify |
| Replay attacks | Idempotency keys; timestamp + nonce in signed requests |

## Compliance certifications (target)

- **SOC 2 Type II:** Required for enterprise; target month 9
- **ISO 27001:** Required for EU enterprise; target month 12
- **PCI DSS:** N/A — we don't process payments
- **HIPAA:** N/A — body data is not health data
- **FedRAMP:** Deferred (no government customers in v1)

## Pen testing

- Annual third-party pen test (Bishop Fox / NCC Group class)
- Continuous bug bounty (HackerOne) — payouts up to $25K for critical
- Internal red team exercises quarterly

## Incident response

- 24/7 on-call via PagerDuty
- P0 incidents (data breach, service down): customer notification within 1 hour
- Post-mortem published to all retailers within 7 days
- SLA credits per MSA for downtime

---

# 17. Required Retailer Data

## What we need from the retailer to integrate

| Data | Purpose | Format | When |
|------|---------|--------|------|
| Signed MSA + DPA | Legal | PDF | Onboarding week 1 |
| Retailer legal entity name + address | Contracts | Text | Onboarding week 1 |
| Billing contact + cost center | Invoicing | Email + address | Onboarding week 1 |
| Technical contact | Support | Email + Slack | Onboarding week 1 |
| Product catalog (initial subset) | Digitization | CSV/JSON/API | Onboarding week 2 |
| Per-SKU: SKU ID, name, category, image URLs, size chart, fabric, color, gender | Digitization input | JSON | With catalog |
| App bundle IDs / package names | SDK credentials | iOS bundle ID, Android package name | Onboarding week 2 |
| Production domains (for SDK script tag on web) | CORS / referrer | List of domains | Onboarding week 2 |
| Webhook URL(s) | Async notifications | HTTPS URLs | Onboarding week 3 |
| OAuth client credentials | Server-to-server auth | Public key (we hold) | Onboarding week 2 |
| SSO configuration (SAML) | Dashboard access | IdP metadata XML | Onboarding week 3 |
| Test shopper accounts | QA | 3-5 accounts in sandbox | Onboarding week 4 |

## What we do NOT require

- We do NOT need retailer's customer database
- We do NOT need retailer's order history (we receive per-purchase attribution via webhook instead)
- We do NOT need retailer's payment credentials
- We do NOT need access to retailer's POS
- We do NOT need retailer's loyalty system

---

# 18. Optional Retailer Data

## Data that improves quality but isn't required

| Data | Why optional | Benefit if provided |
|------|-------------|---------------------|
| Returns data (anonymized) | Improves size recommendation | Better fit → fewer returns → higher ROI |
| Per-SKU fabric weight (gsm) | Improves digitization accuracy | Better drape simulation in Phase 2 3D pipeline |
| Shopper demographic (region only) | Bias detection in try-on quality | Identifies if try-on quality varies by demographic |
| Inventory levels per store | Phase 2: in-store QR scan feature | Lets us surface "in stock at your store" |
| Existing size charts | Better size recommendation | Cross-brand calibration |
| A/B test framework integration | Lets retailer A/B test try-on placement | Cleaner attribution data |

## Data we will NEVER accept

- PII (email, phone, address) of individual shoppers
- Payment card data
- Government IDs
- Health/medical data
- Data from minors (we refuse and require age gate in SDK)

---

# 19. API Endpoints

## Full endpoint catalog (v1)

### Auth
```
POST   /v1/tokens                          # Mint scoped shopper token (S2S)
POST   /v1/tokens/revoke                   # Revoke a shopper token (S2S)
```

### Catalog (server-to-server)
```
POST   /v1/catalog/skus                    # Push SKU(s) for digitization
GET    /v1/catalog/skus                    # List SKUs (paginated)
GET    /v1/catalog/skus/{sku}              # Get SKU status + representation
POST   /v1/catalog/skus/{sku}/redigitize   # Re-digitize a SKU
DELETE /v1/catalog/skus/{sku}              # Remove SKU from platform
POST   /v1/catalog/batch                   # Bulk push (async, returns job_id)
GET    /v1/catalog/batch/{job_id}          # Check bulk push status
```

### Body Profiles (SDK or S2S)
```
POST   /v1/body_profiles                   # Create profile (uploads scan data)
GET    /v1/body_profiles/{id}              # Get profile metadata (NOT raw data)
DELETE /v1/body_profiles/{id}              # Delete profile (shopper-initiated)
POST   /v1/body_profiles/{id}/consent      # Record consent
GET    /v1/body_profiles/{id}/consent      # Get consent history
```

### Try-Ons (SDK only)
```
POST   /v1/tryons                          # Request try-on generation (async)
GET    /v1/tryons/{id}                     # Poll try-on status
GET    /v1/tryons/{id}/image               # Redirect to signed CDN URL
POST   /v1/tryons/{id}/views               # Request additional view (back, side)
```

### Events (SDK only)
```
POST   /v1/events                          # Track event (batched OK)
POST   /v1/events/batch                    # Batch track events
```

### Attribution (S2S, retailer → us)
```
POST   /v1/attribution/purchase            # Report purchase tied to try-on
POST   /v1/attribution/return              # Report return tied to try-on
```

### Analytics (S2S)
```
GET    /v1/analytics/summary               # Aggregate metrics (date range)
GET    /v1/analytics/funnel                # Funnel metrics
GET    /v1/analytics/top_skus              # Top SKUs by try-on
GET    /v1/analytics/returns_delta         # Return rate comparison
```

### Billing (S2S)
```
GET    /v1/billing/usage                   # Current month usage
GET    /v1/billing/invoices                # Historical invoices
GET    /v1/billing/invoices/{id}           # Specific invoice PDF
GET    /v1/billing/forecast                # Forecasted month-end bill
```

### Webhooks (S2S)
```
POST   /v1/webhooks/endpoints              # Register webhook URL
GET    /v1/webhooks/endpoints              # List registered webhooks
DELETE /v1/webhooks/endpoints/{id}         # Remove webhook
POST   /v1/webhooks/endpoints/{id}/test    # Send test event
GET    /v1/webhooks/deliveries             # Delivery history (paginated)
POST   /v1/webhooks/deliveries/{id}/retry  # Manually retry delivery
```

### Health
```
GET    /v1/health                          # Liveness
GET    /v1/status                          # Current incidents
```

## API surface discipline

This is 28 endpoints. That's the right size — small enough to learn in an afternoon, large enough to cover the use case. We will resist adding endpoints unless they unlock a meaningful new use case. API sprawl is a tax on every integration.

---

# 20. SDK Methods

## iOS (Swift)

```swift
// Initialization (once, at app launch)
TryOnSDK.configure(
    with: .init(
        tenantId: "retailer_123",
        environment: .production
    )
)

// Set shopper token (after retailer login)
TryOnSDK.shared.setShopperToken(token: "eyJ...")

// Check if body profile exists
TryOnSDK.shared.hasBodyProfile { hasProfile in
    // ...
}

// Launch body scan flow
TryOnSDK.shared.startBodyScan(
    in: viewController,
    theme: .default,
    completion: { result in
        switch result {
        case .success(let profileId): // ...
        case .failure(let error): // ...
        case .cancelled: // ...
        }
    }
)

// Generate try-on
TryOnSDK.shared.generateTryOn(
    request: .init(
        garmentSKU: "SKU_12345",
        size: .recommended,    // or .explicit("M")
        view: .front
    ),
    completion: { result in /* ... */ }
)

// Display try-on result (drops in as UIViewController)
let viewerVC = TryOnSDK.shared.makeTryOnViewer(
    for: tryonId,
    delegate: self
)
present(viewerVC, animated: true)

// Track custom event
TryOnSDK.shared.trackEvent(
    name: "custom_event",
    attributes: ["key": "value"]
)

// Delete body profile (shopper-initiated)
TryOnSDK.shared.deleteBodyProfile { result in /* ... */ }

// Configure theme
TryOnSDK.shared.setTheme(.init(
    primaryColor: .retailerBrandColor,
    cornerRadius: 12,
    fontFamily: "RetailerSans"
))
```

## Android (Kotlin)

```kotlin
// Initialization
TryOnSDK.configure(
    context = applicationContext,
    config = Config(
        tenantId = "retailer_123",
        environment = Environment.PRODUCTION
    )
)

// Set shopper token
TryOnSDK.instance.setShopperToken("eyJ...")

// Launch scan
TryOnSDK.instance.startBodyScan(
    activity = this,
    theme = Theme.default(),
    callback = object : BodyScanCallback {
        override fun onSuccess(profileId: String) { /* ... */ }
        override fun onError(error: TryOnError) { /* ... */ }
        override fun onCancelled() { /* ... */ }
    }
)

// Generate try-on (coroutine)
val result = TryOnSDK.instance.generateTryOn(
    TryOnRequest(
        garmentSKU = "SKU_12345",
        size = Size.Recommended,
        view = View.FRONT
    )
)

// Display viewer
val intent = TryOnSDK.instance.makeTryOnViewerIntent(
    tryonId = "tryon_abc",
    context = this
)
startActivity(intent)
```

## Web (TypeScript)

```typescript
import { TryOnSDK } from '@tryonsdk/web';

// Initialization
const sdk = await TryOnSDK.configure({
  tenantId: 'retailer_123',
  environment: 'production',
});

// Set shopper token (after retailer login)
await sdk.setShopperToken('eyJ...');

// Launch scan (modal)
const profile = await sdk.startBodyScan({
  theme: { primaryColor: '#FF0000' },
});

// Generate try-on
const tryon = await sdk.generateTryOn({
  garmentSKU: 'SKU_12345',
  size: 'recommended',
  view: 'front',
});

// Display in a div
sdk.renderTryOnViewer({
  container: document.getElementById('tryon-container')!,
  tryonId: tryon.id,
  onEvent: (event) => console.log(event),
});
```

## React Native + Flutter

Thin wrappers over the native SDKs. Same method names, same behaviors. Documented in dedicated integration guides.

---

# 21. Error Handling

## Error categories

| Category | Example | Who handles |
|----------|---------|-------------|
| **Client errors** (4xx) | Invalid token, malformed request, SKU not found | SDK or retailer backend |
| **Server errors** (5xx) | Internal platform error, GPU failure | Us; SDK retries |
| **Network errors** | Timeout, DNS failure, offline | SDK; retries with backoff |
| **Compute errors** | Try-on generation failed (model error) | Us; SDK surfaces fallback UI |
| **Rate limit** (429) | Too many requests | SDK; backs off |
| **Consent errors** | Shopper revoked consent | SDK; shows re-consent flow |
| **Quota errors** | Retailer exceeded monthly commit + overage cap | Retailer dashboard; SDK shows degraded UI |

## Standard error response

```json
{
  "type": "https://docs.tryonsdk.com/errors/garment_not_digitized",
  "title": "Garment not digitized",
  "status": 422,
  "detail": "The requested garment SKU has not been digitized yet.",
  "instance": "req_abc123",
  "errors": [
    {
      "code": "garment_not_digitized",
      "field": "garment_sku",
      "value": "SKU_12345"
    }
  ],
  "retry_after_seconds": null,
  "documentation_url": "https://docs.tryonsdk.com/errors/garment_not_digitized"
}
```

## SDK error taxonomy

```swift
enum TryOnError: Error {
    case networkError(underlying: Error)         // Retryable
    case rateLimited(retryAfter: TimeInterval)   // Retryable
    case serverError(requestId: String)          // Retryable
    case authenticationFailed                    // Not retryable; re-auth
    case consentRevoked                          // Not retryable; re-consent
    case garmentNotDigitized(sku: String)        // Not retryable; UI fallback
    case bodyProfileExpired                      // Not retryable; re-scan
    case quotaExceeded                           // Not retryable; contact retailer
    case validationError(field: String, msg: String)  // Not retryable; fix request
    case unknown(requestId: String)              // Surface to user
}
```

## Retry strategy (SDK)

- Network errors: exponential backoff (1s, 2s, 4s, 8s, 16s) with jitter; max 5 retries
- Server errors: same
- Rate limits: honor `Retry-After` header; default 60s
- All retries respect `Idempotency-Key` to prevent duplicate side effects

## Graceful degradation

When try-on fails, SDK shows:
1. **First:** "Try-on temporarily unavailable. Retrying..." (auto-retry)
2. **After 3 failures:** "We couldn't generate a try-on. Tap to retry, or browse the product images."
3. **Silent fallback:** If retailer configures `fallback_to_product_images: true`, SDK silently shows product images without surfacing the error.

---

# 22. Offline Handling

## Mobile SDK

- **Body scan:** Cannot be performed offline (requires real-time server validation)
- **Try-on requests:** Queued locally (encrypted, max 10) and replayed when online. Shopper sees "Try-on will generate when you're back online" toast.
- **Event tracking:** Always queued locally; uploaded when online (per Section 12)
- **Cached try-on views:** Last 20 try-on results available offline for re-viewing

## Web SDK

- Body scan requires WebXR or webcam; offline impossible
- Try-on requests fail gracefully: "Connect to the internet to try this on"
- Cached results: stored in IndexedDB; available offline for 24h

## Why we don't do offline try-on generation

Try-on inference requires a GPU; shopper devices cannot run the model. We considered on-device distilled models (Phase 2) but they don't meet quality bar for v1. The honesty here matters: **virtual try-on is fundamentally a connected experience in v1.** Retailer's marketing should reflect this.

---

# 23. Rate Limits

## Default limits

| Endpoint | Limit | Burst |
|----------|-------|-------|
| POST /v1/tokens | 100/min per retailer | 200 |
| POST /v1/body_profiles | 10/min per shopper | 20 |
| POST /v1/tryons | 60/min per shopper | 100 |
| POST /v1/events | 1000/min per retailer | 2000 |
| GET /v1/analytics/* | 60/min per retailer | 100 |
| All other endpoints | 600/min per retailer | 1000 |

## Custom limits

Enterprise retailers can request custom limits. We negotiate per deal. Typical enterprise tier: 5,000 req/min for events, 500 req/min for try-ons.

## What happens on limit breach

1. API returns `429 Too Many Requests` with `Retry-After` header
2. SDK backs off automatically
3. Dashboard shows rate limit hits in real-time
4. If sustained breach: we contact retailer to upgrade tier

## Why we rate limit

Not to be stingy — to protect the GPU pool. A single retailer going viral shouldn't degrade service for all others. Rate limits are a fairness mechanism, not a revenue mechanism.

---

# 24. Billing Architecture

## Billing model

```
Per Successful Try-On (definition in Section 26):
  Default:        $0.15 per try-on
  Volume tier 1:  $0.12 per try-on (10K-50K/month)
  Volume tier 2:  $0.10 per try-on (50K-100K/month)
  Volume tier 3:  $0.08 per try-on (100K+/month)

Monthly minimum commit:
  Pilot (first 90 days): $0
  Standard:              $2,000/month
  Enterprise:            $10,000/month (custom terms)

Body scan:              Free (we eat cost)
Catalog digitization:   $25/SKU one-time
                        First 500 SKUs free per retailer
Dashboard/analytics:    Included
Webhook delivery:       Included
Premium support:        $2,000/month (SLA, dedicated CSM)
```

## Billing pipeline

```
tryon.viewed event ──► Event log ──► Usage metering service
                                       │
                                       ├── Dedup (idempotency key)
                                       ├── Apply pricing tier
                                       ├── Record usage record
                                       └── Update monthly total
                                                │
                                                ▼
                                       Billing aggregator
                                       (Stripe Billing)
                                                │
                                                ▼
                                       Monthly invoice
                                       (generated 1st of month)
                                                │
                                                ▼
                                       Retailer pays via ACH/wire
```

## Tech choices

- **Stripe Billing:** Handles invoicing, dunning, tax. Don't build billing.
- **Snowflake (deferred):** For usage analytics at scale; ClickHouse suffices for v1.

## Invoice structure

```
RETAILER INVOICE — July 2026

Try-On Usage:
  Try-ons viewed:                12,847
  Volume tier:                   10K-50K ($0.12)
  Try-on charges:                $1,541.64

Catalog Digitization:
  New SKUs digitized:               127
  Rate:                          $25/SKU
  Digitization charges:          $3,175.00

Monthly minimum commit:          $2,000.00
                                  (waived — usage exceeded minimum)

Premium support:                 $2,000.00

────────────────────────────────────────────
Subtotal:                        $8,716.64
Tax (CA):                          $610.16
────────────────────────────────────────────
Total due:                        $9,326.80
```

## Disputes

- Retailer can dispute any try-on charge within 60 days
- Dispute resolution: we provide event log evidence (timestamp, IP, shopper_token_id)
- If we cannot prove the try-on was viewed by a unique shopper session, we credit the charge

---

# 25. Usage Metering

## What we meter

```
EVENT                    METERED?    BILLABLE?
─────────────────────────────────────────────
tryon_button_tapped     Yes         No
scan_started            Yes         No
scan_completed          Yes         No
tryon_requested         Yes         No
tryon_succeeded         Yes         No
tryon_viewed            Yes         YES (billing trigger)
tryon_failed            Yes         No (we eat cost)
tryon_swiped            Yes         No (cached view, no new compute)
add_to_cart_after_tryon Yes         No
purchase_after_tryon    Yes         No
```

## Deduplication

- `tryon_id` is unique per generation
- `tryon_viewed` events deduped on `tryon_id` within a 24h window (one view per try-on per shopper per day = one billable event)
- Repeated views of the same tryon within 24h = free (cached)
- New day, same tryon, viewed again = free (cached, no new compute)

## Real-time metering

- Usage counter updates within 5 seconds of `tryon_viewed` event
- Dashboard shows live usage
- Alerts at 50%, 80%, 100% of monthly commit
- Auto-throttle at 110% of overage cap (configurable; default = no cap, just alert)

## Audit trail

Every billed event has:
- `tryon_id`
- `shopper_token_id` (anonymized)
- `garment_sku`
- `timestamp`
- `event_id` (SDK-generated UUID)
- `request_id` (platform-generated)

Retailer can download full usage log as CSV from dashboard.

---

# 26. Successful Try-On Definition

## The precise definition

**A "Successful Try-On" is a try-on generation that:**

1. Was requested via `POST /v1/tryons` with a valid body profile ID and a digitized garment SKU
2. Completed with HTTP status `succeeded` and returned a valid image URL
3. Was viewed by the shopper (the SDK fired a `tryon_viewed` event with the corresponding `tryon_id`)
4. The `tryon_viewed` event was the first such event for that `tryon_id` within a 24-hour window

## What is NOT a successful try-on (and therefore not billable)

- Try-on generation failed (any reason: model error, GPU OOM, garment input invalid)
- Try-on succeeded but shopper never viewed the image (closed app, network died, navigated away)
- Try-on was a cached result served from a previous generation within 24h
- Try-on was generated in sandbox environment
- Try-on was generated by retailer's QA team (test mode flag set)
- Try-on was viewed but later determined to be a duplicate event (dedup)
- Try-on was generated during a documented platform outage (auto-credit)

## Why this definition

This is the **most retailer-favorable definition that still keeps us in business.**

- We don't bill on request (retailer pays for failed attempts — bad)
- We don't bill on generation (shopper may never see the image — bad)
- We bill on **viewed** (shopper saw the value — fair)
- We don't bill on cached re-views (no new compute — fair)

**The risk we accept:** if a retailer's UI is bad and shoppers view but don't engage, we still bill. This is acceptable — we delivered the value; the retailer's UI is their responsibility.

## Edge cases

| Scenario | Billed? |
|----------|---------|
| Shopper views try-on, immediately closes app | Yes |
| Shopper views try-on, immediately deletes body profile | Yes |
| Shopper views try-on 5 times in 1 hour | No (1 billable event) |
| Shopper views try-on, comes back next day, views again | No (cached within 24h; new day = still cached, no new generation) |
| Try-on fails, SDK auto-retries, succeeds, shopper views | Yes (only the successful one) |
| Try-on succeeds, image URL leaked, viewed by bot | No (we detect non-shopper user-agents and don't count) |
| Retailer's QA team views try-on in production | No (test mode flag) |
| Try-on generation took 30 seconds (slow) | Yes (we ate the cost; service was delivered) |

---

# 27. Exactly When Billing Occurs

## The precise moment

```
T+0.000s   Shopper taps "Try It On"
T+0.050s   SDK validates profile + SKU
T+0.100s   SDK calls POST /v1/tryons
T+0.300s   Platform returns tryon_id (status: pending)
T+0.500s   GPU picks up job
T+2.000s   Model inference complete
T+2.100s   Image uploaded to CDN
T+2.200s   Webhook fires to retailer
T+2.300s   SDK polls /v1/tryons/{id}, receives image URL
T+2.400s   SDK renders image in viewer
T+2.500s   Image fully painted on screen
T+2.550s   SDK fires tryon_viewed event
T+2.600s   Event hits our ingestion API
T+2.650s   Event validated, deduped
T+2.700s   Usage meter updated
T+2.700s   ◄── BILLING OCCURS HERE
T+2.750s   Webhook fires: tryon.viewed (with billed_amount)
T+3.000s   Dashboard updates with new usage
```

## What triggers the bill

The `tryon_viewed` event arriving at our ingestion API and passing validation. Not the try-on generation. Not the image being served from CDN. The viewed event.

## What does NOT trigger a bill

- Generation without view → no bill
- Cached view → no bill
- Failed generation → no bill
- Bot/scraped view → no bill (we filter)
- Sandbox → no bill
- Test mode → no bill

## Invoicing

- Real-time usage tracking (dashboard live within 5s)
- Monthly invoice generated on 1st of month
- Net-30 payment terms
- Auto-charge to ACH on day 30 (configurable)
- Late payment: 1.5% monthly interest per MSA

---

# 28. Enterprise Onboarding

## Phase 1: Commercial (weeks 1-4)

```
Week 1: Initial conversation
        - Retailer VP Eng/Digital + Our Head of Sales
        - Demo on retailer's actual catalog (we digitize 5 SKUs free)
        - Discuss commercial model

Week 2: Technical discovery
        - Our Solutions Engineer + Retailer Tech Lead
        - Review retailer's mobile stack, PIM, existing try-on (if any)
        - Output: Integration Plan document

Week 3: Commercial negotiation
        - Pricing tier negotiation
        - MSA + DPA drafted
        - Security review initiated (retailer's infosec team)

Week 4: Contract signing
        - MSA signed
        - DPA signed
        - SOW for pilot defined (90 days, 5 stores or 1 mobile app)
```

## Phase 2: Technical onboarding (weeks 5-7)

```
Week 5: Provisioning
        - Tenant created
        - API keys issued (sandbox + prod)
        - Dashboard access (SSO configured)
        - Slack Connect channel opened
        - Solutions Engineer assigned

Week 6: Catalog ingestion
        - Initial 200-500 SKUs ingested
        - Digitization begins
        - Retailer team trained on catalog management

Week 7: SDK installation
        - Mobile team adds SDK to app
        - Web team adds script tag
        - Sandbox integration tested with real catalog
```

## Phase 3: Integration build (weeks 8-12)

```
Week 8-10:  Retailer builds integration
            - "Try It On" button on PDP
            - Scan flow wired
            - Try-on viewer embedded
            - Webhook receiver built
            - Attribution pipeline built (if measuring ROI)

Week 11:    QA
            - Sandbox testing
            - Load testing
            - Accessibility audit
            - Pen test (if retailer requires)

Week 12:    Soft launch
            - Internal employee beta (50-200 users)
            - Bug bash
            - Analytics validation
```

## Phase 4: Production launch (week 13+)

```
Week 13:    Staged rollout
            - 1% of app users
            - Monitor for errors, performance, feedback

Week 14:    10% rollout

Week 15:    50% rollout

Week 16:    100% rollout

Week 17+:   Optimization
            - A/B test button placement
            - Refine scan UX
            - Weekly review with retailer
```

## Total wall-clock: 16 weeks for enterprise, 8-10 weeks for mid-market

This is the realistic timeline. Retailers promising faster are either lying or under-resourcing the integration.

---

# 29. Developer Onboarding

## Self-serve path (for smaller retailers)

```
1. Developer visits tryonsdk.com
2. Signs up with work email (no consumer emails)
3. Verifies company domain
4. Gets sandbox tenant + API keys instantly
5. Reads quickstart docs (15 min)
6. Installs SDK, runs sample app (30 min)
7. Digitizes 5 free SKUs (10 min)
8. Generates first try-on (5 min)
9. Total time to "hello world": ~60 minutes
```

## Documentation structure

```
docs.tryonsdk.com/
├── Quickstart (15 min)
├── Concepts
│   ├── What is a body profile?
│   ├── What is a digitized SKU?
│   ├── How billing works
│   └── Privacy & security
├── Integration guides
│   ├── iOS (Swift)
│   ├── Android (Kotlin)
│   ├── Web (TypeScript)
│   ├── React Native
│   ├── Flutter
│   └── Server-to-server API
├── API reference
├── SDK reference
├── Webhooks
├── Migration guides (v0 → v1)
├── Tutorials
│   ├── Add try-on to Shopify
│   ├── Add try-on to Salesforce Commerce
│   ├── A/B testing try-on
│   └── Measuring ROI
├── Troubleshooting
└── Status page (status.tryonsdk.com)
```

## Sample apps

We publish reference apps for iOS, Android, and Web that demonstrate full integration. Retailer developers can copy-paste patterns. These apps are open-source (MIT licensed) on GitHub.

## Developer support

- **Free:** Docs, status page, community Discord, email support (48h SLA)
- **Standard ($2K/mo):** Slack Connect, 24h SLA, sandbox support
- **Enterprise ($10K/mo):** Dedicated CSM, 4h SLA, named solutions engineer, quarterly business reviews

---

# 30. Estimated Integration Effort

## Per-platform effort

| Component | iOS | Android | Web | Backend |
|-----------|-----|---------|-----|---------|
| SDK install + config | 4h | 4h | 2h | — |
| Shopper token wiring | 8h | 8h | 4h | 16h |
| Try-on button on PDP | 8h | 8h | 4h | — |
| Scan flow integration | 4h | 4h | 8h | — |
| Try-on viewer embedding | 8h | 8h | 8h | — |
| Theme matching | 8h | 8h | 8h | — |
| Event tracking wiring | 4h | 4h | 4h | — |
| Webhook receiver | — | — | — | 16h |
| Attribution pipeline | — | — | — | 24h |
| Analytics dashboard embed | — | — | — | 8h |
| Testing + QA | 16h | 16h | 8h | 16h |
| **Total per platform** | **60h** | **60h** | **46h** | **80h** |

## Total effort for full multi-platform integration

- **iOS + Android + Web + Backend:** ~250 engineering hours
- **At 40h/week per engineer:** ~6 engineer-weeks
- **With 3 engineers (1 mobile, 1 web, 1 backend) in parallel:** ~2 weeks wall-clock
- **Realistic with meetings, code review, QA:** 4-6 weeks wall-clock

## Effort by retailer maturity

| Retailer type | Effort | Wall-clock |
|---------------|--------|-----------|
| Shopify DTC brand | 80h | 2 weeks |
| Mid-market mobile-only retailer | 120h | 3 weeks |
| Mid-market omnichannel (mobile + web) | 200h | 5 weeks |
| Enterprise (mobile + web + complex backend) | 350h | 8-10 weeks |
| Enterprise (legacy backend, multiple brands) | 500h+ | 12-16 weeks |

## The honest pitch to retailers

"This is a 4-6 week integration for a mid-market retailer with mobile and web apps. Two engineers (one mobile, one backend) can do it. We provide a solutions engineer for the first 2 weeks at no cost."

---

# 31. Team Size Required

## Retailer team

| Role | Allocation | Duration |
|------|-----------|----------|
| Mobile engineer (iOS or Android) | 50% | 6 weeks |
| Web engineer (if web integration) | 50% | 4 weeks |
| Backend engineer | 50% | 6 weeks |
| Product manager | 25% | 8 weeks |
| Designer (for theme matching) | 25% | 2 weeks |
| QA engineer | 50% | 4 weeks |
| DevOps (for webhook receiver) | 25% | 2 weeks |

**Total retailer effort:** ~2.5 FTE for 6 weeks

## Our team (per active integration)

| Role | Allocation | Duration |
|------|-----------|----------|
| Solutions Engineer | 50% | 12 weeks |
| Customer Success Manager | 25% | Ongoing |
| Implementation Engineer (catalog) | 100% | 4 weeks |

## Scaling our team

At any given time, we can support:
- **10 concurrent integrations** with 5 solutions engineers
- **20 active retailers** with 3 CSMs
- **Unlimited** (within reason) with self-serve developer onboarding

## The Stripe analogy

Stripe supports thousands of integrations with a small solutions engineering team because the SDK is good and the docs are great. Our goal: same. Self-serve for 80% of integrations; solutions engineer only for top 20% enterprise.

---

# 32. Third-Party Dependencies

## Cloud / infrastructure

| Service | Use | Alternative | Switching cost |
|---------|-----|-------------|----------------|
| AWS (us-east-1, eu-west-1) | Compute, storage | GCP, Azure | Medium — Terraform-managed |
| Cloudflare | CDN, WAF, DNS, Pages | Fastly, AWS CloudFront | Low |
| Cloudflare R2 | Image storage | AWS S3 | Low (S3-compatible API) |
| AWS KMS | Encryption keys | GCP KMS, HashiCorp Vault | Medium |
| Stripe Billing | Invoicing, tax, dunning | Chargebee, Zuora | High (core system) |
| Auth0 | Dashboard SSO (SAML) | Ory, Okta | Medium |

## Data / ML

| Service | Use | Alternative |
|---------|-----|-------------|
| HuggingFace Hub | Model weights storage | S3 + custom |
| Weights & Biases | Experiment tracking | MLflow |
| Arize AI | Production ML observability | Fiddler, Evidently |
| Scale AI | Data annotation (Phase 2) | Labelbox, internal |

## Communication / ops

| Service | Use |
|---------|-----|
| Slack | Retailer Connect channels |
| Linear | Issue tracking |
| PagerDuty | On-call |
| Statuspage | Public status page |
| Sentry | Error tracking (SDK + backend) |
| Datadog | Backend observability |
| Mixpanel | Product analytics (internal) |

## Build vs. buy decisions

| Component | Build | Buy | Why |
|-----------|-------|-----|-----|
| Try-on model | Build (fine-tune) | — | Core IP |
| Body scan pipeline | Build | — | Core IP |
| Garment digitization | Build | — | Strategic moat |
| Billing | — | Buy (Stripe) | Don't reinvent |
| Auth | — | Buy (Auth0) | Don't reinvent |
| CDN | — | Buy (Cloudflare) | Don't reinvent |
| Observability | — | Buy (Datadog, Sentry) | Don't reinvent |
| Email | — | Buy (Resend) | Don't reinvent |

---

# 33. Cloud Architecture

## Topology

```
                        ┌──────────────────────────┐
                        │   Cloudflare (global)    │
                        │   - CDN (image delivery) │
                        │   - WAF                  │
                        │   - DNS                  │
                        │   - DDoS protection      │
                        └────────────┬─────────────┘
                                     │
                ┌────────────────────┴────────────────────┐
                │                                         │
        ┌───────▼────────┐                      ┌─────────▼────────┐
        │  US-East-1     │                      │  EU-West-1       │
        │  (Virginia)    │                      │  (Ireland)       │
        │                │                      │                  │
        │  - API gateway │                      │  - API gateway   │
        │  - Auth svc    │                      │  - Auth svc      │
        │  - Catalog svc │                      │  - Catalog svc   │
        │  - Try-on svc  │                      │  - Try-on svc    │
        │  - Billing svc │                      │  - Billing svc   │
        │  - Webhook svc │                      │  - Webhook svc   │
        │  - GPU pool    │                      │  - GPU pool      │
        │  - Postgres    │                      │  - Postgres      │
        │  - Redis       │                      │  - Redis         │
        │  - Kafka       │                      │  - Kafka         │
        │  - ClickHouse  │                      │  - ClickHouse    │
        │  - S3 / R2     │                      │  - S3 / R2       │
        └────────────────┘                      └──────────────────┘
```

## Service breakdown (12 services)

1. **API Gateway** (Envoy or Kong) — auth, rate limit, routing
2. **Auth Service** (Go) — token issuance, validation, revocation
3. **Catalog Service** (Go) — SKU CRUD, digitization status
4. **Digitization Service** (Python) — garment pipeline orchestration
5. **Body Profile Service** (Go) — encrypted profile storage
6. **Try-On Service** (Go) — job queue, status tracking
7. **Inference Service** (Python + PyTorch) — model serving on GPUs
8. **Event Service** (Go) — event ingestion, Kafka producer
9. **Analytics Service** (Go + ClickHouse) — query layer
10. **Billing Service** (Go) — usage metering, Stripe integration
11. **Webhook Service** (Go) — outbound webhook delivery + retries
12. **Dashboard Backend** (Node/TS) — dashboard API

## Deployment

- **ECS Fargate** for stateless services (simpler than K8s for our scale; we'd switch to EKS at >30 services)
- **RDS Aurora Postgres** for transactional data (multi-AZ)
- **ElastiCache Redis** for caching, dedup, rate limiting
- **MSK Kafka** for event streaming
- **ClickHouse Cloud** for analytics (managed, scales automatically)
- **S3 + Cloudflare R2** for image storage (R2 for hot images, S3 for cold)
- **GPU instances:** g5.xlarge warm pool (4-8 instances per region)

## Cost estimate (monthly, at 100K try-ons/month)

| Component | Monthly cost |
|-----------|-------------|
| GPU pool (8 g5.xlarge, 70% utilization) | $4,800 |
| ECS Fargate (12 services, 2 replicas each) | $1,200 |
| RDS Aurora Postgres (db.r6g.large, multi-AZ) | $600 |
| ElastiCache Redis (cache.r6g.large) | $350 |
| MSK Kafka (2 brokers) | $800 |
| ClickHouse Cloud | $600 |
| S3 storage (10TB) | $230 |
| Cloudflare (CDN + R2 + Workers) | $400 |
| Networking (data transfer, NAT, etc.) | $500 |
| Datadog + Sentry + observability | $1,500 |
| **Total** | **~$11,000/month** |

**Per try-on cost:** $11,000 / 100,000 = $0.11/try-on
**Selling price:** $0.15/try-on (default tier)
**Gross margin:** 27% at default tier, 47% at tier 3 ($0.08 cost / $0.15 price)

**Margin improvement levers:**
- Larger GPU instances (g5.2xlarge) amortize cold start better
- Distilled model for sub-1s inference (cuts GPU cost 50%)
- Caching more aggressive (10-20% of try-ons served from cache = free)

Target gross margin by year 2: 70%+ via these levers.

---

# 34. Edge Architecture

## What runs at the edge (Cloudflare Workers)

- **Image delivery:** CDN-cached try-on images served from Cloudflare edge PoPs (300+ globally)
- **Signed URL validation:** Worker validates signed URLs at edge (no origin hit)
- **Rate limiting:** Per-IP and per-tenant limits enforced at edge
- **Geo-routing:** EU requests routed to eu-west-1; US to us-east-1
- **Bot detection:** Worker fingerprints user-agents, blocks obvious bots (protects billing integrity)
- **A/B test routing:** Worker assigns shoppers to experiment variants without origin call

## What does NOT run at the edge

- Try-on inference (requires GPU; not available at edge)
- Body profile storage (compliance: must stay in region)
- Auth (requires database lookup; not edge-cacheable)
- Event ingestion (requires Kafka; not edge-friendly)

## Edge caching strategy

| Asset | TTL | Cache key |
|-------|-----|-----------|
| Try-on images | 24 hours | tryon_id |
| Garment images (from catalog) | 7 days | sku + version |
| SDK JavaScript bundle | 1 hour (revalidate) | SDK version |
| API responses (GET /catalog/skus/{sku}) | 5 minutes | sku + retailer_id |

---

# 35. Mobile Architecture

## iOS-specific

- **Language:** Swift 5.9+
- **UI:** UIKit (not SwiftUI) for v1 — broader compatibility, more control
- **Camera:** AVFoundation + ARKit (LiDAR on Pro devices)
- **Networking:** URLSession with async/await
- **Storage:** Keychain (tokens), CoreData (cache), FileManager (large blobs)
- **ML:** Core ML for on-device quality checks; server-side for inference
- **Distribution:** XCFramework via Swift Package Manager
- **Min iOS:** 15.0 (covers 95%+ of active devices)
- **LiDAR-required features:** iOS 15+ on iPhone 12 Pro and later

## Android-specific

- **Language:** Kotlin 1.9+
- **UI:** Jetpack Compose for viewer; View system for camera interop
- **Camera:** CameraX + ARCore
- **Networking:** OkHttp + Kotlin Coroutines
- **Storage:** EncryptedSharedPreferences (tokens), Room (cache)
- **ML:** ML Kit for on-device quality checks; TFLite for future on-device inference
- **Distribution:** AAR via Maven Central
- **Min Android:** API 29 (Android 10, covers 85%+ of active devices)
- **ARCore-required:** ARCore 1.40+

## Web-specific

- **Bundle:** ESM module + IIFE fallback
- **Tree-shakeable:** Retailers import only what they use
- **Camera:** MediaDevices API + WebXR (for WebXR-capable browsers)
- **Storage:** IndexedDB for cache; Web Crypto for encryption
- **Workers:** Web Worker for body scan processing (don't block main thread)
- **Browser support:** Chrome 100+, Safari 15+, Firefox 100+, Edge 100+
- **No IE11 support.** (It's 2026.)

## Cross-platform concerns

- **Body scan UX:** Slightly different per platform (iOS guide shows 360° rotation; Android fallback shows 2-pose flow). SDK abstracts this; retailer doesn't code different flows.
- **Performance budgets:** Aggressive — we will not let the SDK degrade the host app's performance. We run our own benchmarks on every release.
- **Crash safety:** SDK never crashes the host app. All errors caught and surfaced gracefully.

---

# 36. Future API Expansion

## Phase 2 (12-18 months out)

| Feature | API | Pricing |
|---------|-----|---------|
| Size recommendation | `POST /v1/size_recommendations` | $0.05 per recommendation |
| Multi-garment try-on (outfit) | Extended `POST /v1/tryons` | $0.20 per outfit try-on |
| Back/side views | Extended `POST /v1/tryons` | $0.05 per additional view |
| Video try-on (3s rotation) | `POST /v1/tryons` with `video: true` | $0.30 per video |
| In-store QR scan flow | New SDK module | Free (drives try-on billing) |
| Shopper "try-on history" widget | SDK component | Free (improves engagement) |
| Webhook: returns delta | `POST /v1/attribution/return` (already in v1) | Free |

## Phase 3 (18-36 months out)

| Feature | API | Pricing |
|---------|-----|---------|
| 3D try-on (Phase 2 from prior strategy) | New API surface | Premium tier |
| On-device try-on (distilled model) | SDK-only, no API call | Per-device license |
| Cross-retailer avatar portability | `POST /v1/body_profiles/import` | Free for shopper |
| Brand SDK (for brand-direct integration) | Separate SDK | Per-brand license |
| Marketplace analytics (anonymized cross-retailer benchmarks) | Dashboard feature | Premium tier |

## What we will NOT add

- Recommendation engine (Algolia, Bloomreach exist)
- Search (same)
- Loyalty (retailer owns)
- Checkout (retailer owns)
- Customer service chat (not our problem)
- Reviews (Yotpo, Bazaarvoice exist)

**Discipline:** Saying no to feature creep is how we stay integrable. Every added feature is a tax on every integration.

---

# 37. Biggest Engineering Risks

## Top 10 engineering risks

| Rank | Risk | Severity | Mitigation |
|------|------|----------|------------|
| 1 | **Try-on quality inconsistent across body types/skin tones** | Critical | Bias testing in CI; diverse evaluation set; manual QC sampling |
| 2 | **GPU cold start kills UX** | Critical | Warm pool always-on; predictive scaling; pre-warm on app open |
| 3 | **SDK bloat causes app rejection or retailer pushback** | High | Strict size budgets; lazy loading; modularity |
| 4 | **Multi-tenancy data leak between retailers** | High | Schema-per-tenant; automated pen test on every release |
| 5 | **Biometric compliance failure (BIPA class action)** | High | DR-011 architecture; external counsel review; cyber insurance |
| 6 | **Webhook delivery reliability** | Medium | At-least-once + idempotency; retailer must dedup; clear docs |
| 7 | **SDK backwards compatibility breakage** | Medium | Semantic versioning; deprecation policy; automated compat tests |
| 8 | **Catalog digitization throughput bottleneck** | Medium | Parallelized pipeline; auto-scaling; manual QC fallback |
| 9 | **Cloud cost runaway** | Medium | DR-023 circuit breaker; per-retailer cost allocation |
| 10 | **SDK crash in host app** | High | Defensive programming; crash-free SDK is non-negotiable; Sentry in SDK |

## Risks we accept

- **Single cloud (AWS):** Accept for v1; multi-cloud is over-engineering. Mitigated by Terraform.
- **Single CDN (Cloudflare):** Accept for v1; Fastly as warm backup if needed.
- **Stripe dependency:** Accept; switching cost is real but justified by Stripe's quality.

---

# 38. Biggest Business Risks

## Top 10 business risks

| Rank | Risk | Severity | Mitigation |
|------|------|----------|------------|
| 1 | **Retailer churn: pilots don't convert to long-term deals** | Critical | Attribution dashboard proves ROI; quarterly business reviews |
| 2 | **"Why pay when shoppers don't convert?" — retailer disputes value** | Critical | Tiered pricing; free pilot period; clear ROI case studies |
| 3 | **Big tech (Apple/Google) launches free first-party try-on** | Critical | Position as multi-platform; retailers won't accept Apple-only |
| 4 | **3DLOOK or competitor launches similar SDK** | High | Speed; digitization moat; lock-in via catalog data |
| 5 | **Retailer integration takes too long → deal dies** | High | Self-serve docs; solutions engineer support; realistic timelines |
| 6 | **Unit economics break at scale (GPU cost grows faster than revenue)** | High | Distilled model R&D; caching; tiered pricing |
| 7 | **Privacy scandal (any try-on company) tars entire category** | High | Proactive privacy posture; PR strategy; industry leadership |
| 8 | **Talent acquisition (ML/CV engineers scarce)** | Medium | Remote-first; competitive comp; meaningful work |
| 9 | **Retailer goes bankrupt mid-contract** | Medium | DPA allows data return; monthly billing limits exposure |
| 10 | **Investor narrative shifts away from retail AI** | Medium | Position as AI infrastructure, not retail tech (DR-021) |

---

# 39. Recommended MVP

## What to build first (months 1-4)

```
Month 1-2:
  - iOS SDK only (Android + Web deferred)
  - Body scan flow (iPhone Pro LiDAR)
  - Try-on API + inference service (CatVTON fine-tuned)
  - Catalog ingestion (push API only)
  - Basic dashboard (usage + billing)
  - Webhook delivery (tryon.succeeded, tryon.viewed, billing.threshold_reached)

Month 3:
  - Android SDK (ARCore + 2-photo fallback)
  - Web SDK (basic)
  - Analytics dashboard (funnel, top SKUs)
  - Attribution webhook receiver

Month 4:
  - 1 pilot retailer integration (sandbox → production)
  - Catalog digitization pipeline (target: 500 SKUs in week 1 of pilot)
  - Stripe Billing integration
  - SOC 2 Type I readiness
```

## What to defer

- React Native + Flutter wrappers (let community build until we have scale)
- Multi-region (US-only for v1; EU in month 6)
- Size recommendation (Phase 2)
- 3D try-on (Phase 2+)
- On-device inference (Phase 3)
- Cross-retailer avatar portability (Phase 3)
- Mall operator features (deleted from roadmap entirely in this model)

## MVP success criteria

- 1 retailer live in production with 200+ digitized SKUs
- 1,000+ try-ons generated in first month
- >70% try-on success rate (generation → viewed)
- <$0.10 cost per try-on
- >40% scan completion rate
- Net Promoter Score from retailer's engineering team >30

## What "done" looks like for MVP

A retailer can:
1. Sign up via self-serve or enterprise path
2. Install SDK in iOS app in <1 day
3. Push 200 SKUs to platform; digitized in 1 week
4. Launch try-on to 100% of app users
5. See analytics dashboard with real data
6. Pay per try-on via Stripe
7. Receive webhooks for every event
8. Measure ROI via attribution webhook

---

# 40. Final Recommendation

## The strategic case

This pivot from consumer-app to enterprise-SDK is **the single biggest improvement to the company's viability** I've seen in our discussions. It:

- Eliminates customer acquisition cost (retailer has the shoppers)
- Eliminates identity friction (retailer has the accounts)
- Eliminates catalog acquisition cost (retailer provides their own)
- Eliminates checkout complexity (retailer's existing flow)
- Aligns pricing with value (per successful try-on)
- Creates a defensible moat (digitization pipeline + retailer lock-in)
- Produces a venture-scale path (200-500 retailers × $200-500K/yr)

## What I'd change about the brief

1. **"Pay only when successful try-on is generated"** — I refined this to "pay when try-on is successfully generated AND viewed." This protects us from eating failed-generation costs while remaining retailer-friendly. (Section 26.)

2. **"Stripe of Virtual Try-On"** — Half-right. Better framing: "Stripe for integration + Algolia for usage-based pricing + Segment for data flow." This composite framing changes design decisions around webhooks, analytics, and SDK ergonomics. (Section 1.)

3. **The brief implies a consumer-facing "Westside/Lifestyle/H&M app"** — clarified that we are NOT in those apps' UI; we are a feature inside them. The retailer's brand is front-and-center; we are invisible to the shopper.

## What we should do next

1. **Build the MVP per Section 39** — iOS SDK + API + 1 pilot retailer in 4 months
2. **Sign 1 launch retailer** — Preferably mid-market premium (Aritzia, Reformation, Vuori-tier) with strong mobile app and digitally-sophisticated shopper base
3. **Hire 2 ML engineers, 2 mobile engineers, 2 backend engineers, 1 solutions engineer, 1 designer** — 8 people to MVP
4. **Raise $3-5M seed** on the back of the pilot retailer LOI + MVP demo
5. **Target Series A** at $2-3M ARR with 5+ retailers, 18 months post-seed

## The brutal honest read

This is a **fundable, venture-scale company** if we execute. The enterprise SDK model is right. The pricing model (refined) is right. The moat (digitization) is real. The technical risks are tractable. The market timing is correct.

The three things that will determine success:
1. **Can we ship an iOS SDK that doesn't crash retailer apps?** (Engineering execution)
2. **Can we sign 1 launch retailer in 90 days?** (Sales execution)
3. **Can we digitize 500 SKUs in 1 week?** (Pipeline execution — this is the moat)

If all three are yes, this is a $100M+ ARR company in 5 years. If any one is no, we have a problem.

**Recommendation: Proceed. Build the MVP. Sign the pilot. Raise the seed.**

---

# Appendix: Startup Decision Register Update

New architectural decisions from this Enterprise SDK blueprint (appended to `/home/z/my-project/decision_register.md`):

- **DR-024** — Strategic pivot from consumer app to enterprise SDK + API platform
- **DR-025** — Refined "successful try-on" billing definition (generation AND viewed)
- **DR-026** — Hybrid pricing: $0.15/try-on + $2K/mo minimum commit + $25/SKU digitization
- **DR-027** — Three-layer auth: S2S OAuth + scoped SDK tokens + biometric consent
- **DR-028** — Retailer owns shopper identity; we hold opaque shopper_ref only
- **DR-029** — No cross-retailer profile merging by default; portability is opt-in (Phase 2)
- **DR-030** — iOS SDK first (Swift, UIKit, iOS 15+); Android month 3; Web month 3
- **DR-031** — React Native + Flutter wrappers deferred until community demand proven
- **DR-032** — Try-on images cached 24h; re-views are free (no rebilling)
- **DR-033** — Stripe Billing for invoicing; do not build billing
- **DR-034** — ClickHouse for analytics (not Snowflake) at v1 scale
- **DR-035** — ECS Fargate (not EKS) until >30 services
- **DR-036** — Cloudflare R2 for hot image storage (zero egress), S3 for cold
- **DR-037** — SOC 2 Type II target by month 9, ISO 27001 by month 12
- **DR-038** — Say-no list: no recommendations, no search, no loyalty, no checkout, no reviews
- **DR-039** — Self-serve dev onboarding for 80% of integrations; solutions engineer for top 20%
- **DR-040** — Cloud cost circuit breaker (DR-023 reaffirmed for this model)
- **DR-041** — API versioning: URL-based (/v1/); 24-month stability promise; 6-month deprecation notice
- **DR-042** — Webhook retries: 6 attempts over 24h; disable after 6 failures
- **DR-043** — Body scan free for retailer; we eat cost (it's the funnel)
- **DR-044** — Mall operator features removed from roadmap in SDK model

Full details with Evidence Required / Owner / Priority / Status will be appended to the register file.

---

*End of Retailer Integration Blueprint v1.0. Ready for retailer CTO/VP Eng review.*
