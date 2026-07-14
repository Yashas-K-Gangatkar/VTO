# Architecture Documentation

This directory holds all architecture and engineering documentation for the VTO platform.

## Documents

| Document | Purpose |
|----------|---------|
| [`decision-register.md`](decision-register.md) | 85 architectural decisions (DR-001 through DR-085) — the constitutional law of this codebase |
| [`market-validation.md`](market-validation.md) | Market sizing, customer segmentation, competitive landscape, company-killer risks |
| [`retailer-integration-blueprint.md`](retailer-integration-blueprint.md) | Enterprise SDK + API blueprint (40 sections) — what retailers see before integrating |
| [`ai-engine-architecture.md`](ai-engine-architecture.md) | AI/ML architecture (18 sections) — IDM-VTON pipeline, optimization, evaluation |
| [`implementation-blueprint.md`](implementation-blueprint.md) | Production implementation plan (12 sections, 100 engineering tasks) |

## ADRs

Architecture Decision Records live in [`adr/`](adr/). Each ADR explains a single decision in detail. ADRs are numbered and immutable once accepted — superseding an ADR requires a new ADR.

Format:
```
# ADR-XXX: Title

## Status
Accepted | Superseded by ADR-YYY | Deprecated

## Context
Why this decision was needed

## Decision
What we decided

## Consequences
What changes because of this decision

## Alternatives Considered
What else we looked at and rejected
```

## Runbooks

Per-service on-call runbooks live in [`runbooks/`](runbooks/). Each runbook covers:
- Common alerts and how to respond
- On-call escalation paths
- Service-specific debugging tips
- Post-incident review template

## Onboarding

New engineer? Start at [`onboarding/README.md`](onboarding/README.md).

## Security

Security documentation, threat models, and SOC 2 evidence in [`security/`](security/).
