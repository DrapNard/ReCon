# Flutter to iOS Gap Analysis

## Features matched exactly (current baseline)
- Auth API contract and cached-login lifecycle semantics.
- Core tab shell structure.
- Sessions/worlds fetch and basic detail rendering.
- Theme setting persistence and sign-out behavior.

## Features adapted for iOS conventions
- Material navigation/components mapped to SwiftUI `TabView` + `NavigationStack`.
- Snackbar-style errors mapped to iOS-standard inline/error text and alerts where appropriate.

## Features deferred
- Full inventory action parity (selection/download/delete/share).
- Full message content subtype parity beyond text baseline.
- Full profile and status-management parity.
- Panorama parity implementation.

## Technical debt introduced/removed
- Introduced: temporary in-memory cache path pending persistent parity backend finalization.
- Removed: Flutter plugin dependency chain for native iOS path.

## Known limitations
- Some Flutter features intentionally disabled in source remain disabled for literal parity.
- Checklist marks current implementation status and should be treated as source of truth.
