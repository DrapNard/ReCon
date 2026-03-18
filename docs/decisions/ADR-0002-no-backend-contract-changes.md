# ADR-0002: Preserve Existing Backend Contracts

## Status
Accepted

## Context
Migration must not depend on server-side changes and should maintain compatibility with current backend behavior.

## Decision
Native iOS client uses existing REST/hub endpoints, headers, payload shapes, and semantics with no contract changes.

## Consequences
- Pros: lower coordination overhead, reduced rollout risk.
- Cons: client may retain some legacy API quirks.
