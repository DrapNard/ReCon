# ADR-0003: SwiftUI + Observation + URLSession

## Status
Accepted

## Context
Need modern, maintainable iOS-first architecture targeting iOS 18.

## Decision
Use SwiftUI for UI, Observation-style stores on main actor, URLSession for REST/websocket, Keychain for secrets, UserDefaults for simple settings.

## Consequences
- Pros: minimal dependencies, native performance and maintainability.
- Cons: requires deliberate architecture discipline during parity expansion.
