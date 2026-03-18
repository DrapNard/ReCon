# ADR-0001: Parallel Native iOS App Strategy

## Status
Accepted

## Context
The repository contains a production Flutter app used across multiple platforms. Replacing in place increases release risk and complicates parity validation.

## Decision
Create a separate native iOS app under `ios-native/` while preserving the Flutter app unchanged.

## Consequences
- Pros: safer rollout, cleaner diffs, easier rollback, straightforward parity comparisons.
- Cons: temporary duplication of app shell and business logic.
