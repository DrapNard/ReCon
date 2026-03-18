# Flutter to Native iOS Migration Plan

## Executive summary
A parallel native iOS app (`ios-native`) will be built to replace Flutter iOS functionality with SwiftUI + native frameworks while preserving backend contracts and literal feature parity.

## Scope
- In scope: iOS app implementation, architecture, tests, docs, CI build/test path.
- Out of scope: backend API changes, Flutter Android/Linux/Windows replacement.

## Migration principles
- Preserve behavior first, then refine UX where iOS compliance requires.
- Keep changes incremental, auditable, and reversible.
- Do not claim parity without checklist evidence.

## Phase breakdown
1. Discovery audit + parity checklist.
2. Target architecture definition.
3. Native scaffold and app bootstrap.
4. Core parity (auth, tabs, sessions/worlds, chat baseline, settings/profile).
5. Advanced parity (inventory/media/realtime edge cases/notifications).
6. Testing hardening + CI + documentation completion.

## Risks
- Realtime protocol incompatibility.
- Inventory upload/download flow regressions.
- Rich text rendering mismatches.

## Decisions made
- Parallel app strategy (`ios-native`).
- iPhone-first v1.
- No API/server contract changes.
- Native Xcode project + optional SPM.

## Open issues
- Final persistent cache backend selection (SwiftData vs SQLite fallback).
- Panorama preview implementation strategy and performance envelope.

## Rollback / parallel-run strategy
- Flutter app remains untouched for existing platforms and fallback validation.
- Native iOS can be enabled independently and validated flow-by-flow against Flutter behavior.
