# ADR-003: Multi-tenancy via retailer_id + RLS

## Status
Accepted (DR-075). Supersedes DR-008 (which originally specified schema-per-tenant).

## Context
Need to isolate retailer data. Options:
- Database-per-tenant
- Schema-per-tenant (Postgres schemas)
- Row-Level Security with `retailer_id` column
- Application-level filtering only

## Decision
Use `retailer_id` foreign key on every tenant-scoped table + Postgres Row-Level Security policies.

## Consequences
- Simple at low tenant count; scales to thousands
- Single migration applies to all tenants
- Connection pool shared across tenants (no per-tenant connection exhaustion)
- RLS provides defense-in-depth: even if application code forgets to filter, Postgres enforces isolation
- Trade-off: RLS policies must be carefully written and pen-tested; one bad policy = cross-tenant leak

## Alternatives Considered
- **Database-per-tenant:** Rejected — operational overhead, no leverage at scale
- **Schema-per-tenant (DR-008 original):** Rejected after analysis — migration fan-out becomes unmanageable beyond 50 tenants; connection pool exhaustion; harder to do cross-tenant analytics
- **Application-only filtering:** Rejected — single bug = cross-tenant data leak; no defense-in-depth

## Implementation

Every tenant-scoped table:
```sql
CREATE TABLE catalog.skus (
    id UUID PRIMARY KEY,
    retailer_id UUID NOT NULL REFERENCES public.retailers(id),
    -- ...
);

ALTER TABLE catalog.skus ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON catalog.skus
    USING (retailer_id = current_setting('app.retailer_id')::UUID);
```

Application sets `app.retailer_id` at transaction start:
```go
tx.Exec(ctx, "SET LOCAL app.retailer_id = $1", retailerID)
```
