# ADR-001: Use Go for backend services

## Status
Accepted (DR-072)

## Context
We need to choose a primary language for backend services. Options considered:
- Go
- Rust
- Python
- Node.js / TypeScript
- Java / Kotlin

## Decision
Use Go for all backend services. AI engine remains Python (DR-072). Dashboard is TypeScript.

## Consequences
- Excellent performance and concurrency primitives (goroutines)
- Distroless Docker images (10-20MB) — minimal attack surface
- Strong standard library, minimal external deps
- Fast compilation, simple deployment (single binary)
- Trade-off: less expressive type system than Rust; no sum types until 1.18+ generics

## Alternatives Considered
- **Rust:** Rejected — operational overhead, slower iteration, talent pool smaller
- **Python:** Rejected for backend — performance, GIL, deployment complexity (acceptable for AI only)
- **Node.js/TS:** Rejected — single-threaded, npm ecosystem fragility, less suited for high-throughput services
- **Java/Kotlin:** Rejected — JVM overhead, more verbose, slower startup than Go
