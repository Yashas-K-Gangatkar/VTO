# Market Validation Report
## Universal Mobile Virtual Try-On Ecosystem for Physical Retail

**Phase:** Market Validation
**Date:** 2026-07-10
**Author:** CTO / Principal Architect (acting in strategy capacity)
**Status:** DRAFT v1 — for founder review

> Methodology: bottom-up sizing where possible, top-down sanity checks, public-market competitor data where available. Where data is thin or private, assumptions are explicitly flagged.

---

# 1. Market Size

## Methodology

Bottom-up: count target stores × realistic pricing × realistic penetration.
Top-down sanity check: global retail tech spend, virtual try-on market estimates.

## Bottom-up sizing

### Global physical apparel retail stores (2024 estimates)

| Region | Total Apparel Stores | Organized / Addressable | Notes |
|--------|---------------------|------------------------|-------|
| USA | ~100,000 | ~30,000 | Mid-large chains, malls |
| EU | ~250,000 | ~50,000 | UK, DE, FR, IT, ES dominate |
| India | ~150,000 | ~5,000 | Mostly unorganized retail; only large chains viable |
| APAC (ex-India) | ~600,000 | ~120,000 | China, Japan, Korea, SEA |
| Rest of World | ~100,000 | ~35,000 | LatAm, MEA |
| **Total** | **~1,200,000** | **~240,000** | |

### Pricing assumptions (per store, annualized)

- Base SaaS: $300/month = $3,600/year
- Per-try-on fee: $0.10 × 100 try-ons/month = $120/year
- Revenue share: 1% × ~$50K incremental revenue/store/year = $500/year
- **Blended ARPU per store: ~$4,200/year**

### TAM (10-year horizon — infrastructure layer aspiration)

| Component | Calculation | Value |
|-----------|-------------|-------|
| Store SaaS | 240,000 × $4,200 | $1.0B |
| Brand licensing | 2,000 brands × $50K | $100M |
| Mall operator licensing | 1,500 malls × $150K | $225M |
| SDK/API layer | 10% uplift on above | $135M |
| Adjacent (size rec, analytics, returns platform) | 50% uplift | $750M |
| **TAM** | | **~$2.2B/year** |

Top-down sanity check: global retail tech spend ~$50B, virtual try-on segment ~$2B today projected $15-20B by 2030. Our 10-year TAM of $2.2B implies ~10-15% share of try-on market. Reasonable if we win infrastructure positioning; aggressive if we don't.

### SAM (3-5 year serviceable)

US + EU focus first. ~80,000 stores reachable in 5 years.

| Region | Reachable Stores (5yr) | ARPU | SAM |
|--------|----------------------|------|-----|
| USA | 30,000 | $4,200 | $126M |
| EU | 50,000 | $4,200 | $210M |
| India | 5,000 | $2,500 | $13M |
| APAC | 30,000 | $2,500 | $75M |
| **SAM** | | | **~$424M/year** |

### SOM (realistic 3-year capture)

Assume 5% penetration of SAM in US/EU, minimal elsewhere.

| Region | Penetration | Stores | ARR |
|--------|-------------|--------|-----|
| USA | 5% | 1,500 | $6.3M |
| EU | 3% | 1,500 | $6.3M |
| India | 0.5% | 25 | $0.1M |
| APAC | 0.3% | 90 | $0.2M |
| Brand licenses | — | 10 brands | $1.0M |
| Mall deals | — | 5 malls | $0.8M |
| **SOM (3yr)** | | | **~$14.7M ARR** |

| Horizon | Target |
|---------|--------|
| SOM (3yr) | $15M ARR |
| SOM (5yr) | $50M ARR |
| SOM (7yr) | $120M ARR (venture-scale threshold) |

**Honest read:** Reaching $100M ARR in 7 years requires ~25,000 stores or equivalent brand/mall mix. That's 30% of US reachable stores. Aggressive but not implausible IF unit economics work and we become infrastructure (not just an app).

---

# 2. Customer Segmentation

## Segment ranking by attractiveness

| Rank | Segment | Pain | Budget | Sales Cycle | Switching Cost | Revenue Potential | Score |
|------|---------|------|--------|-------------|----------------|-------------------|-------|
| 1 | Premium apparel brands (DTC + wholesale) | High (returns 30-40%) | Medium | 3-6 mo | Medium | $50-200K/brand/yr | **9/10** |
| 2 | Athletic/sportswear brands | Very high (fit-critical) | High | 3-6 mo | Medium | $100-300K/brand/yr | **9/10** |
| 3 | Premium denim brands | Very high (fit-critical) | Medium | 3-4 mo | Low | $30-100K/brand/yr | **8/10** |
| 4 | Specialty retailers (Aritzia, Free People) | High | Medium | 4-6 mo | Medium | $200-500K/retailer/yr | **8/10** |
| 5 | Department stores | Medium (declining) | Low (cost pressure) | 9-12 mo | High | $500K-2M/retailer/yr | **6/10** |
| 6 | Mall operators | Low (indirect ROI) | Medium | 9-18 mo | Very high | $100-500K/mall/yr | **5/10** |
| 7 | Fast fashion (Zara, H&M, Uniqlo) | Low (low margin, low return rate) | High | 12+ mo | Very high | $1-3M/brand/yr | **5/10** |
| 8 | DTC brands (Allbirds, Everlane) | High (returns) | Low | 2-4 mo | Low | $30-80K/brand/yr | **6/10** |
| 9 | Big-box apparel (Target, Walmart) | Low | High | 12-18 mo | Very high | $2-5M/retailer/yr | **4/10** |
| 10 | Retail software companies (Shopify, Salesforce Commerce) | None directly | High | 6-12 mo | High | Platform rev share | **4/10 (later)** |
| 11 | POS vendors (NCR, Lightspeed) | None directly | Medium | 6-9 mo | Medium | Integration rev | **3/10 (later)** |
| 12 | Fashion marketplaces (Zalando, ASOS) | High (returns) | High | 12+ mo | Very high | $1-3M/yr | **5/10** |

## Per-segment analysis (top 5 detailed)

### #1 — Premium apparel brands
- **Pain:** 30-40% return rates destroying margin; online returns cost $10-25/unit; physical returns cause out-of-stock
- **Budget:** Marketing/innovation budget, $50-200K annual pilots common
- **Buying process:** Brand innovation lead → CMO/CDO → CFO sign-off
- **Sales cycle:** 3-6 months for pilot; 9-12 months to enterprise deal
- **Existing solutions:** 3DLOOK, Bold Metrics, True Fit, in-house teams
- **Switching barriers:** Catalog digitization investment (we own if digitization is our pipeline)
- **Revenue potential:** $50-200K/brand/year, scaling to $500K with full integration

### #2 — Athletic/sportswear
- **Pain:** Compression/performance fit is highly individual; returns + reviews damage brand
- **Budget:** High (Nike, Lululemon, Adidas have $100M+ innovation budgets)
- **Buying process:** Innovation team → VP Product → CTO/CIO
- **Sales cycle:** 3-6 months (athletic brands move faster than fashion)
- **Existing solutions:** 3DLOOK (Nike uses), Bold Metrics (Lululemon uses)
- **Switching barriers:** Existing multi-year contracts; data integration
- **Revenue potential:** $100-300K/brand/year

### #3 — Premium denim
- **Pain:** Fit is the entire category; one wrong size = return; sizing across brands is wildly inconsistent
- **Budget:** Medium (smaller brands — AG, Mother, Frame, Reformation's denim)
- **Buying process:** Founder/CEO (smaller brands); innovation lead (larger)
- **Sales cycle:** 3-4 months
- **Existing solutions:** 3DLOOK, True Fit, generic size charts
- **Switching barriers:** Low — these brands are underserved
- **Revenue potential:** $30-100K/brand/year

### #4 — Specialty fashion retailers (Aritzia, Free People, Anthropologie)
- **Pain:** High return rates + high cost of physical fitting room space + showrooming
- **Budget:** Medium-high
- **Buying process:** Innovation/digital team → COO → CFO
- **Sales cycle:** 4-6 months pilot
- **Existing solutions:** In-house, point solutions
- **Switching barriers:** Medium — POS integration friction
- **Revenue potential:** $200-500K/retailer/year

### #6 — Mall operators (NOT a beachhead)
- **Pain:** Low and indirect. Mall operators care about footfall, tenant satisfaction, lease renewals — not apparel returns
- **Budget:** Real estate OpEx, very different procurement process than retail tech
- **Buying process:** Mall marketing/innovation team → GM → corporate REIT procurement
- **Sales cycle:** 9-18 months (REIT procurement is famously slow)
- **Existing solutions:** Mall loyalty apps (Simon, Brookfield), existing analytics (RetailNext)
- **Switching barriers:** Long leases, existing vendor relationships
- **Revenue potential:** $100-500K/mall/year — but this is marketing spend, not infrastructure spend
- **Verdict:** Defer to Phase 2. Selling to malls first was the original brief's biggest strategic error.

---

# 3. Competitive Landscape

## Critical context: The Zeekit cautionary tale

**Zeekit** was acquired by Walmart in 2021 for a reported $100M+ and shut down as a consumer product in 2023. The technology was absorbed into Walmart.com's online try-on. **Lesson:** Even with Walmart's resources, standalone virtual try-on (online, B2C) didn't generate enough value to justify a separate brand. The physical-retail-mobile-QR angle is genuinely uncracked — but Zeekit's history means investors will ask hard questions about why this will work where Zeekit didn't.

## Competitor categories

### A. Virtual Try-On (direct functional competitors)

| Company | Funding | Customers | Strengths | Weaknesses | Pricing | Why we win | Why we lose |
|---------|---------|-----------|-----------|------------|---------|------------|-------------|
| **Revery.ai** | ~$5M | ~30 brands | E-com try-on, AI catalog digitization | Online-only; no physical retail | $0.05-0.20/image | Physical retail + persistent avatar | They own online; we can't win there |
| **Fashn.ai** | Bootstrapped/seed | Devs, small brands | API-first, cheap, fast | No avatar, no physical retail | $0.05-0.15/image | Avatar + retail integration | They undercut us on commodity API |
| **Tangiblee** | ~$15M | ~100 retailers | Visualization, multi-category (furniture, jewelry) | Not apparel-specialized; no avatar | Per-store SaaS | Apparel-specific + avatar | They have broader catalog |
| **Vue.ai** | ~$30M | ~100 retailers | Broader retail AI suite | Try-on is one feature, not core | Enterprise license | Focus + quality | They bundle, harder to displace |
| **Zeekit (Walmart)** | Acquired | Walmart.com | Infinite resources if Walmart chose to extend | Sunset as standalone; absorbed | Internal | We're independent; multi-brand | Walmart could re-launch tomorrow |
| **Zalando internal** | Private | Zalando only | Massive dataset, in-house team | Captive use only | Internal | We serve other brands | They could spin out as SaaS |

### B. 3D Body Scanning / Sizing (adjacent competitors)

| Company | Funding | Strengths | Weaknesses | Threat Level |
|---------|---------|-----------|------------|--------------|
| **3DLOOK** | ~$15M | Market leader, 100+ brands, BIPA-compliant | Sizing only, not try-on; 2-photo approach | **HIGH** — could pivot to try-on |
| **Bold Metrics** | ~$10M | Deep in athletic (Lululemon), questionnaire-based | No scan, lower accuracy | Medium |
| **PrimeAI** | UK-based, kiosk model | UK retail traction | Kiosk-only, no mobile | Medium |
| **MTailor** | Bootstrapped | Direct consumer app | DTC only, not B2B | Low |

### C. Magic Mirrors / In-Store Tech

| Company | Funding | Strengths | Weaknesses | Threat Level |
|---------|---------|-----------|------------|--------------|
| **MemoMi (MemoryMirror)** | ~$20M | Neiman Marcus, existing deployments | Hardware-heavy, expensive, single-station | Low (different model) |
| **Oak Labs** | ~$10M | Smart fitting rooms | Fitting room tech, not try-on | Low |
| **Perch** | Acquired by RichRelevance | Interactive displays | Display tech, not try-on | Low |

### D. Retail AI / Analytics

| Company | Funding | Strengths | Weaknesses | Threat Level |
|---------|---------|-----------|------------|--------------|
| **Syte.ai** | ~$30M | Visual search, retailer traction | Not try-on | Low |
| **Lily AI** | ~$30M | Product attribution AI | Not try-on | Low |
| **Caper (Instacart)** | Acquired | Smart cart, in-store tech | Grocery focus | Low |

### E. Enterprise Retail Software / POS (potential partners, not competitors initially)

| Company | Position | Why they matter |
|---------|----------|-----------------|
| **Shopify** | E-com platform for DTC brands | Integration partner, not competitor |
| **Salesforce Commerce Cloud** | Enterprise e-com | Integration partner; could build try-on as feature |
| **NCR** | POS hardware/software | Legacy, slow — unlikely to build try-on |
| **Lightspeed** | SMB retail POS | Potential distribution channel |
| **Square** | SMB POS | Potential distribution channel |

### F. Digital Humans / Avatars

| Company | Funding | Strengths | Weaknesses | Threat Level |
|---------|---------|-----------|------------|--------------|
| **Ready Player Me** | ~$15M | Gaming avatar platform | Not retail-focused | Low |
| **Soul Machines** | ~$50M+ | Hyper-realistic digital humans | B2B customer service, not retail try-on | Low |
| **Meta Human Creator (Epic)** | Internal | Game-grade quality | Not measurement-grade; not retail | Low |

### G. Computer Vision Giants (latent threats)

| Company | Why they matter | Threat Level |
|---------|------------------|--------------|
| **Apple (ARKit, Vision Pro)** | Owns the iPhone depth pipeline; could launch first-party try-on | **HIGH** long-term |
| **Google (ARCore)** | Owns Android; could launch first-party try-on | **HIGH** long-term |
| **Meta (Spark AR)** | Owns AR consumer behavior; could pivot to commerce | Medium |
| **TikTok / ByteDance** | Try-on filters exist; massive consumer distribution | Medium |
| **Snapchat** | Try-on Lenses; Gen Z audience | Medium |

## Threat ranking (composite)

1. **3DLOOK** — adjacent, well-funded, could pivot into try-on. They have the brand relationships.
2. **Apple first-party** — exists in 3-5 year horizon if AR glasses / Vision Pro Lite succeed
3. **Revery.ai** — most likely to recognize the physical-retail angle and pivot
4. **Walmart (Zeekit tech)** — could re-emerge as B2B SaaS if they choose
5. **Big tech (Google, Meta)** — latent, not active
6. **Tangiblee** — could expand from visualization into try-on

**Honest read:** The competitive landscape is fragmented and no one owns physical-retail-mobile-try-on. That's a white space — but it's also a yellow flag. Either we see something they don't, or the unit economics don't work and they've already figured that out.

---

# 4. Market Timing

## Why NOW (the bull case)

| Factor | What changed | Why it matters |
|--------|-------------|----------------|
| **Diffusion-based VITON** | CatVTON (2024), OOTDiffusion (2024) — first commercially-acceptable open-source try-on models | Previously you needed custom in-house ML teams. Now any competent ML engineer can fine-tune. Cuts MVP build time by 12+ months. |
| **iPhone LiDAR maturity** | 4 years of ARKit Body Capture improvements | Body scan on consumer phone now viable at ±1cm. Wasn't true in 2020. |
| **Mobile NPUs** | A17 Pro, Snapdragon 8 Gen 3 — first time on-device diffusion inference is realistic | Could move try-on to device in 12-24 months, killing GPU cost concern |
| **Post-pandemic returns crisis** | Apparel returns 30-40%, up from 20-25% pre-2020 | Brands actively seeking solutions; budget allocated |
| **Enterprise AI budget unlock** | Post-ChatGPT, every retailer has AI budget line items | Buyers actively looking; 2023-2024 was hardest sell cycle, now easier |
| **Store labor costs** | Retail wages up 25-40% post-pandemic in US/EU | "Save staff time" pitch lands now in ways it didn't in 2019 |
| **Gen Z consumer behavior** | AR native via Snapchat/TikTok filters | Expectation of interactive try-on experience exists; not a behavior change required |
| **Mall operator desperation** | US mall vacancy at 10-year highs | Operators willing to try new experiences to drive footfall |

## Why NOT yet (the bear case)

| Factor | Counter-argument |
|--------|------------------|
| **On-device inference still marginal** | A17 Pro can run distilled diffusion at 5-10s/image, not real-time AR. Server-side still required for quality. |
| **Diffusion model quality still uneven** | Hands, faces, complex garments still fail frequently. Quality ceiling unclear for fashion-grade use. |
| **Retailer IT modernization is slow** | Even with AI budget, integration cycles are 6-12 months. Tech readiness ≠ commercial readiness. |
| **Consumer privacy sentiment** | Body scanning feels invasive to many shoppers; adoption unknown. |
| **Economic uncertainty** | Retailers cutting innovation budgets in 2024-2026 if recession hits. |

## Timing verdict

**Window opens 2025-2026, closes 2028-2029.** The diffusion-based try-on breakthrough is the unlock. Apple/Google first-party solutions are 3-5 years out. We have a ~24-month window to establish infrastructure position before big tech notices.

---

# 5. Barriers to Entry

## Barriers that protect us

| Barrier | Strength | Why |
|---------|----------|-----|
| **Retail relationships** | High | Each enterprise retail deal is 6-12 months of relationship-building. Cannot be shortcut. First-mover advantage compounds. |
| **Garment digitization pipeline** | High | This is the actual moat. Once a brand has 1000 SKUs digitized in our format, switching means re-digitizing. Lock-in via data. |
| **Composite technical stack** | Medium | CV + ML + mobile + retail integration is hard to assemble. Single-vendor competitors typically have only 2-3 of these. |
| **Regulatory (biometric)** | Medium | BIPA/GDPR compliance architecture is expensive to retrofit. Late entrants face the same cost; we eat it early. |
| **Network effects (later)** | Low→High | Shoppers with avatars in our system = utility for next brand. Brand with SKUs in our format = utility for next shopper. Compounds over time. |

## Barriers that hurt us

| Barrier | Why it hurts |
|---------|--------------|
| **Enterprise sales cycles** | 6-12 months per retailer. Even with perfect execution, revenue ramps slowly. Cash burn > revenue for first 18 months. |
| **Brand trust** | New entrant with no track record. Need reference accounts to break through. |
| **Capital requirements** | GPU inference + body scan dataset + retail sales team = $5-10M to Series A. Higher than typical SaaS. |
| **Existing multi-year contracts** | Brands locked into 3DLOOK/True Fit/Bold Metrics contracts. Replacement cycle is 2-3 years. |
| **Big tech optionality** | Apple/Google can offer first-party for free. We can't compete on price if they enter. |

---

# 6. Moat Analysis

## Moat ranking

| Rank | Moat | Strength | Build time | Notes |
|------|------|----------|-----------|-------|
| 1 | **Garment digitization pipeline + data** | Strong | 12-18 mo | Once brands have 1000+ SKUs in our format, switching cost is enormous. This is the moat. |
| 2 | **Shopper avatar network effect** | Strong (long-term) | 24-36 mo | Once 1M+ shoppers have avatars in our system, every brand wants in. Cold start problem. |
| 3 | **Retail integration depth** | Strong | 12-24 mo | POS + inventory + commerce stack integration per retailer. Hard to replicate. |
| 4 | **Returns data flywheel** | Medium-Strong | 18-30 mo | Returns data → better size rec → fewer returns → more data. Compounds. |
| 5 | **Brand-side lock-in** | Medium | 12-18 mo | Once brand digitizes catalog with us, switching means re-doing it. |
| 6 | **Try-on model fine-tuning** | Medium | 6-12 mo | Fine-tuned on real catalog data; proprietary weights. Easily replicated if competitor has equivalent data. |
| 7 | **Compliance architecture** | Medium | 6 mo | BIPA/GDPR-grade architecture is a barrier, not a moat. Late entrants face same cost. |
| 8 | **SDK / Developer API** | Low→Medium | 18-24 mo | Only a moat if we have distribution. Otherwise just a feature. |
| 9 | **Brand recognition** | Low | 24+ mo | B2B brand builds slowly. Not defensible alone. |
| 10 | **Privacy posture** | Low | — | Table stakes, not moat. Compliance failures destroy; compliance doesn't differentiate. |

## Moat strategy

The defensible moat is the **garment digitization pipeline + shopper avatar network effect**. Every decision should optimize for:

1. Becoming the cheapest, fastest way to digitize garments (P4 in technical roadmap)
2. Making the avatar portable across brands (so shopper acquisition compounds)
3. Owning the format/standard for "virtual garment representation" — if competitors must adopt our format, we win even if they copy the tech

The single biggest strategic risk is treating try-on inference (P5) as the moat. **It isn't.** Diffusion models commoditize in 18 months. The digitization pipeline is the moat.

---

# 7. Business Model

## Pricing model evaluation

| Model | Pros | Cons | Verdict |
|-------|------|------|---------|
| Per Store SaaS | Predictable, simple | Doesn't capture value from usage | **Component of hybrid** |
| Per Mall | Large contracts | Slow sales cycle, indirect ROI | Phase 2 |
| Per Scan | Aligns with usage | One-time per customer; low LTV | **Reject** |
| Per Try-On | Aligns with value | Variable cost; margin pressure | **Component of hybrid** |
| Per Active User | SaaS-aligned | Hard to attribute; low per-user value | **Reject** |
| Enterprise License | Large deals | Long sales cycle; binary outcomes | Phase 2 |
| API Usage | Developer-friendly | Commoditizes pricing | Long-term |
| Revenue Share | Aligns incentives | Hard to attribute; brand-resistant | **Component of hybrid** |
| Marketplace | Network effects | Chicken-and-egg | Long-term |
| **Hybrid** | Captures multiple value streams | Complex to communicate | **RECOMMENDED** |

## Recommended hybrid pricing (MVP)

```
Per Store, per month:
  Base SaaS:        $300/month
  Includes:         100 try-ons/month, basic analytics
  Per additional try-on: $0.10
  Revenue share on attributed purchases: 1% (capped at $500/store/month)

Per Brand, per year:
  Catalog digitization: $50/SKU one-time (first 500 SKUs free for launch partner)
  Brand license: $50K/year (includes SDK, analytics dashboard)

Per Mall, per year (Phase 2):
  Site license: $100-250K/year (includes all stores in mall)
  Booth deployment: $30K CapEx + $1K/month maintenance
```

## Unit economics (target)

| Metric | Target | Notes |
|--------|--------|-------|
| Gross margin (SaaS component) | 90% | Pure software |
| Gross margin (try-on variable) | 50% | $0.05 cost / $0.10 price |
| Gross margin (blended) | 80%+ | Required for venture scale |
| CAC (brand) | $30-50K | Enterprise sales |
| LTV (brand) | $300K+ (3yr) | Annual + digitization + try-on |
| LTV/CAC | 6:1+ | Healthy |
| Payback period | 12-18 mo | Acceptable for enterprise SaaS |

## Honest assessment

The revenue share component is critical — without it, we're selling a feature, not infrastructure. If we can prove try-on drives 5-15% incremental purchases per store, the revenue share alone is $5K-15K/store/year — larger than the SaaS component. **Attribution measurement is a critical engineering investment, not a feature.**

---

# 8. Go-To-Market Strategy

## Beachhead

**Premium fashion brand with 50-200 stores, high return rate, digitally-native-but-physical presence.**

### First customer — Aritzia or Reformation (or similar)
- **Why:** Digitally sophisticated, fashion-forward, 50-150 stores, known return pain, shopper demographic = iPhone-Pro-owning millennials/gen-Z (matches DR-003 iPhone-first decision)
- **Deal structure:** Free pilot for 90 days in 3-5 stores; 200 SKU digitization included; commit to 50-store rollout at $300/month + $0.10/try-on + 1% rev share after pilot success
- **Success metrics:** 30%+ try-on-to-purchase conversion, 10%+ return rate reduction, NPS >40

### Second customer — Adjacent premium fashion brand
- **Candidates:** Reformation, Gilt, AG Jeans, Mother Denim, Frame, Alo Yoga, Vuori
- **Strategy:** Use Customer #1 as reference; target brand with similar shopper demographic to leverage existing avatar base
- **Goal:** Land 2-3 brands in 12 months

### Third customer — Department store or specialty retailer
- **Candidates:** Nordstrom, Anthropologie (Anthropologie Group), Free People, Saks Fifth Avenue
- **Strategy:** Now we have brand references + multi-brand avatar network. Pitch department store as "the aggregator" — every brand they carry, we already support
- **Goal:** Land by month 18

### Mall operator (Phase 2 — year 2)
- **Candidates:** Simon Property, Brookfield, Westfield, Macerich
- **Strategy:** Use brand + retailer traction to negotiate mall-wide license. Mall operator pays for booth deployment as footfall driver
- **Goal:** 3-5 mall deals by month 24

### International expansion (Phase 3 — year 3)
- **UK/EU first** (Westfield UK, Selfridges, Galeries Lafayette)
- **Defer India/APAC** until year 4+ — different retail structure, lower ARPU

## Pilot strategy (first 90 days)

```
Week 1-2:   Catalog digitization (200 SKUs from launch partner)
Week 3-4:   App + brand co-branding, store staff training
Week 5-12:  Pilot in 3-5 stores
            - QR codes on garment tags
            - Store staff trained to demo
            - In-store signage
            - Shopper incentive: 10% off first purchase via try-on
Week 13:    Pilot review with brand — convert or kill
```

---

# 9. Company Killers — Top 50 Risks

Ranked by severity. T1 = existential, T2 = major, T3 = moderate.

| Rank | Risk | Severity | Mitigation |
|------|------|----------|------------|
| 1 | **Try-on quality not good enough** — shoppers don't trust the image, conversion doesn't move | T1 | Validation Track A in weeks 1-12; kill criteria defined |
| 2 | **Brand partner doesn't convert pilot to deal** — we lose 6 months | T1 | Multi-pipeline from day 1; 3 LOIs before committing |
| 3 | **Body scan adoption too low** — shoppers won't scan | T1 | UX research early; fallback to 2-photo approach |
| 4 | **Unit economics don't work** — GPU cost > revenue per try-on | T1 | Validation Track E; aggressive cost engineering |
| 5 | **Big tech enters** — Apple/Google launches free first-party try-on | T1 | Move up-stack to infrastructure/data layer; don't compete on inference |
| 6 | **Garment digitization too slow** — can't onboard brands fast enough | T1 | Validation Track C; <10 min/SKU hard target |
| 7 | **3DLOOK pivots to try-on** — they have brand relationships we don't | T1 | Out-execute; lock brands with digitization data lock-in |
| 8 | **Fundraising environment deteriorates** — runway cuts short | T1 | Lean MVP; raise 18+ months runway per round |
| 9 | **BIPA class-action lawsuit** — biometric compliance failure | T1 | DR-011 compliance architecture from day 1; cyber liability insurance |
| 10 | **Brand churn > 30%** — pilots don't convert to long-term deals | T1 | Attribution measurement; clear ROI dashboards for brand |
| 11 | **Model bias scandal** — try-on quality worse for darker skin / larger bodies | T1 | Bias testing in Validation Track A; diverse test dataset |
| 12 | **Hiring failure** — can't recruit CV/ML talent in 6-month window | T2 | Founder-led recruiting; remote-first; contractor fallback |
| 13 | **Retail IT can't integrate** — POS systems block deployment | T2 | Start with no-POS MVP (DR-005); QR + app only |
| 14 | **Shopper app uninstall rate too high** — one-time use, no retention | T2 | Persistent avatar utility; cross-brand portability |
| 15 | **Brand pricing pressure** — race to bottom on per-try-on fees | T2 | Hybrid pricing; revenue share as primary |
| 16 | **Network effect never kicks in** — brands don't see value of cross-brand avatar | T2 | Avatar portability marketing; shopper-side acquisition |
| 17 | **Store staff don't push the experience** — passive resistance | T2 | In-store training; staff incentives; UX that needs no staff |
| 18 | **Mall operators refuse booth deployment** — Phase 2 strategy collapses | T2 | Phone-first MVP doesn't need booths (DR-002) |
| 19 | **Returns data acquisition fails** — brands won't share | T2 | Anonymized aggregate; alternative: partner with returns platform (Optoro, Loop) |
| 20 | **Garment digitization quality variance** — some categories fail | T2 | Per-category quality gates; manual QC fallback |
| 21 | **Competitor (Revery/Tangiblee) launches physical retail product first** | T2 | Speed; lock launch partner exclusively for 12 months |
| 22 | **Try-on latency > 5s on bad cellular** — in-store WiFi spotty | T2 | Edge caching; pre-compute popular SKUs; offline fallback |
| 23 | **Multi-tenant data leak** — Brand A sees Brand B catalog | T2 | DR-008 schema isolation; pen test before each tenant onboarding |
| 24 | **Avatar quality complaints** — "I don't look like that" | T2 | Body shape slider (DR-002 long-term); honest marketing |
| 25 | **Apple App Store rejection** — biometric consent flow flagged | T2 | Pre-submit review with Apple; legal review of consent flow |
| 26 | **GDPR data subject requests overwhelm** — can't process in 72h | T2 | Automated DSAR pipeline from day 1 |
| 27 | **Key-person risk** — founder departs | T2 | Vesting; documentation; co-founder equity |
| 28 | **Vendor lock-in (AWS GPU shortage)** — can't scale | T2 | Multi-region; secondary cloud plan for GPU |
| 29 | **Consumer backlash on AI-generated images** — "fake" perception | T2 | Marketing positioning: "preview" not "photograph" |
| 30 | **Brand marketing misalignment** — try-on conflicts with brand aesthetic | T2 | Brand approval workflow for try-on outputs |
| 31 | **Competing on features not value** — race to add features vs. prove value | T3 | Strict MVP discipline; kill list maintained |
| 32 | **Store-level data quality** — inaccurate SKU tagging in stores | T3 | QR code on hangtag, not shelf; brand-side QC |
| 33 | **Internationalization friction** — currency, language, sizing standards | T3 | Defer to year 2+ |
| 34 | **Pricing complexity confuses buyers** | T3 | Single-page pricing; ROI calculator |
| 35 | **Investor fatigue with retail tech** — category out of favor | T3 | Position as AI/infrastructure, not retail tech |
| 36 | **Vendor dependency (Auth0/KMS outage)** | T3 | Multi-vendor where possible |
| 37 | **Contractor quality variance** — digitization QC inconsistent | T3 | Standardized training; sample-based audit |
| 38 | **Mobile app store fees** — Apple/Google 15-30% if purchases happen in-app | T3 | All purchases via retailer POS; we don't process transactions |
| 39 | **Returns attribution disputed** — brand claims no impact | T3 | A/B test design from pilot day 1; third-party audit |
| 40 | **App engagement decay** — initial novelty wears off | T3 | Continuous catalog refresh; seasonal push |
| 41 | **Sizing standardization fails across brands** — "M" means different things | T3 | Per-brand calibration; don't claim universal sizing |
| 42 | **Retailer cancels pilot early** — mid-quarter procurement freeze | T3 | Pilot contracts with cancellation fees |
| 43 | **Negative press on body image** — "promotes unhealthy body image" | T3 | Body-positive marketing; diverse avatar library |
| 44 | **IP litigation** — patent troll or competitor suit | T3 | Patent search; IP insurance; clean-room documentation |
| 45 | **Cloud cost overruns** — inference spend exceeds plan | T3 | Hard cost alerts; circuit breaker on spend |
| 46 | **Data residency laws (Germany, Russia, China)** | T3 | Multi-region from day 1 (DR-009) |
| 47 | **Competitor buys market share** — acquires brand with exclusive contract | T3 | Non-exclusivity clauses; multi-brand dependency |
| 48 | **Talent retention** — ML engineers poached by big tech | T3 | Equity refresh; meaningful work; technical reputation |
| 49 | **App store review delays** — update blocked | T3 | Staged rollout; web fallback for critical flows |
| 50 | **Macro recession** — retail budgets cut | T3 | Position as cost-saving (returns reduction) not innovation |

## Top 10 critical risks (the ones that kill the company)

The first 10 risks on the list above are existential. They are:
1. Try-on quality insufficient
2. Brand pilot doesn't convert
3. Body scan adoption too low
4. Unit economics fail
5. Big tech enters
6. Garment digitization too slow
7. 3DLOOK pivots into our space
8. Runway cut short
9. BIPA litigation
10. Brand churn > 30%

**Mitigation summary:** Risks 1, 4, 6 are addressed by Validation Tracks A, E, C. Risks 2, 10 require multi-pipeline sales and rigorous attribution. Risk 3 requires UX research. Risk 5 requires infrastructure positioning. Risk 7 requires speed. Risk 8 requires capital discipline. Risk 9 requires compliance architecture (DR-011).

---

# 10. Decision Register Update

New decisions from this market validation phase: persisted to `/home/z/my-project/decision_register.md` (full format with Evidence Required, Owner, Priority, Status). Summary below:

- **DR-013** — Beachhead customer is premium fashion brand (not mall operator)
- **DR-014** — Hybrid pricing: SaaS + per-try-on + revenue share
- **DR-015** — Attribution measurement is critical-path engineering, not feature
- **DR-016** — Garment digitization pipeline is the strategic moat, not try-on inference
- **DR-017** — Launch partner exclusivity: 12-month exclusive in exchange for free pilot
- **DR-018** — Defer mall operator sales to Phase 2 (year 2+)
- **DR-019** — Defer international expansion to Phase 3 (year 3+), UK/EU first
- **DR-020** — Risk kill criteria: Validation Track A failure = company pivot or shutdown
- **DR-021** — Position as AI/infrastructure company, not retail tech, for investor narrative
- **DR-022** — Reject per-scan and per-active-user pricing models
- **DR-023** — Cloud cost circuit breaker: hard cap at 30% of monthly revenue

Full details in the register file.

---

# 11. Final Verdict

## Should this startup exist?

**Conditionally yes.** The white space is real (no one owns physical-retail-mobile-try-on). The technical timing is real (diffusion VITON breakthrough in 2024). The market pain is real (30-40% apparel returns). The unit economics are plausible (80%+ blended gross margin achievable). The moat is defensible (garment digitization + avatar network).

**But:** Three conditions must be true, or this startup should not exist:

1. **Validation Track A passes** — try-on quality is "good enough" for >60% of shoppers to skip the fitting room. If the diffusion models aren't there yet, this is a research project, not a company.
2. **A launch brand partner commits** — without a real brand with real SKUs and real return data, we're building a demo.
3. **Attribution can be measured** — if we can't prove try-on drives incremental purchases, we're a feature, not infrastructure, and we'll be priced like a feature.

## Would I invest?

**Pre-validation: No.** Too many T1 risks unaddressed. The Zeekit cautionary tale would keep me up at night.

**Post-validation (Tracks A, B, C pass + LOI from launch brand): Yes, at seed, up to $500K-1M.** The validation de-risks the technical story; the LOI de-risks the commercial story.

## Would Y Combinator likely fund it?

**Probably yes, with the right team.** YC funds teams more than ideas. If the founding team has retail or CV credibility, this is a YC-shaped problem:
- Clear technical risk that can be de-risked in 12 weeks (their model)
- Large market with clear pain
- B2B SaaS economics they understand
- AI narrative they're funding aggressively

**Caveat:** YC would push hard on "why not just be an API for online try-on first?" The physical-retail angle is harder to defend in a YC partner meeting. Need a crisp answer.

## Would Sequoia likely fund it?

**Unlikely at pre-seed. Likely at Series A with $1-3M ARR.** Sequoia's enterprise team would want:
- 5+ paying enterprise customers
- $1-3M ARR
- Clear path to $100M ARR
- Founder-market fit (retail or CV background)
- Defensible moat narrative (digitization pipeline + network effect)

Pre-seed at Sequoia is rare unless founder has prior breakout success. Realistic Sequoia check: Series A, 12-18 months after seed, at $1-3M ARR with 5+ brands as customers.

## Would Andreessen Horowitz likely fund it?

**Possibly at seed.** a16z has been more aggressive in AI seed investments post-2023. Their retail/AI thesis (via Connie Chan, Jeff Jordan historically) would find this interesting if:
- Strong technical founding team (CV/ML credibility)
- Clear AI/infrastructure narrative (not "retail tech")
- LOI from launch brand
- Validation Track A results showing >60% try-on satisfaction

a16z would also push on "what if Apple does this for free?" — the answer must be infrastructure positioning (digitization + network effects, not inference).

## Milestones required before institutional investors seriously consider investing

For **seed ($2-4M raise)**:
1. Validation Tracks A, B, C pass
2. Signed LOI from launch brand (12-month exclusivity)
3. 200 SKUs digitized in pilot-ready format
4. Closed beta with 100 shoppers, >60% try-on satisfaction
5. Unit economics validated: <$0.05/try-on, <$10 min/SKU digitization
6. Team of 4-6 engineers with at least 1 ML/CV specialist
7. Compliance architecture (DR-011) reviewed by external counsel

For **Series A ($10-20M raise)**:
1. 3-5 paying brand customers at $100K+ ARR each
2. $1-3M ARR
3. 5,000+ shopper avatars in system
4. Net revenue retention >110%
5. Clear path to $50M ARR in 24 months
6. Reference customers willing to take investor calls
7. At least 1 department store or specialty retailer in pilot
8. Attribution data showing try-on → purchase lift

## Brutal honest summary

This startup has a real chance at becoming a venture-scale company, but the path is narrow. The three biggest killers are try-on quality, brand pilot conversion, and big-tech entry. The single biggest strategic error in the original brief was leading with mall operators — that path is 18 months slower and 10x harder than leading with premium brands.

The single biggest opportunity the original brief missed is the **garment digitization pipeline as the actual moat**. The brief treated digitization as a chore; it's actually the company. If we become the cheapest, fastest way for any brand to digitize its catalog into a portable, try-on-ready format, we win even if every other piece is commoditized.

**Recommendation:** Proceed to seed-stage fundraise contingent on Validation Tracks A, B, C passing and a signed brand LOI. Do not raise Series A until $1M ARR and 3+ paying brands. If Validation Track A fails, kill the company and return capital — do not pivot into "online try-on API" because that market is already occupied and commoditizing.

---

*End of Market Validation Report v1. Ready for founder review.*
