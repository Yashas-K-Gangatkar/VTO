# @vto/contracts

Single source of truth for the VTO API. Contains:
- openapi.yaml — the OpenAPI 3.1 spec (hand-maintained)
- generated/ — auto-generated clients (TypeScript, Go, Python)

## Workflow

1. Edit openapi.yaml
2. Run pnpm gen:all (or make gen-clients)
3. Commit both the spec change AND the generated files
4. Open PR — CI verifies generated files are up to date

## Commands

| Command | Description |
|---------|-------------|
| pnpm validate | Lint the spec with Redocly |
| pnpm gen:typescript | Generate TypeScript client |
| pnpm gen:go | Generate Go client |
| pnpm gen:python | Generate Python client |
| pnpm gen:all | Run all three + validate |
| pnpm clean | Remove all generated files |

## CI enforcement

The CI pipeline runs pnpm gen:all on every PR that touches openapi.yaml.
If the generated files dont match what is committed, the PR fails.
This prevents drift between the spec and the clients.
