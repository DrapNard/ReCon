# iOS Target Architecture (iOS 18, SwiftUI)

## Architectural style
- **Feature-oriented Clean SwiftUI architecture** with pragmatic boundaries.
- Layers:
  - `App`: bootstrap, root routing, dependency container.
  - `Features`: screen/view/store by user capability.
  - `Data`: DTO mapping + repositories.
  - `Infrastructure`: HTTP, websocket hub, keychain, local persistence, notifications.
  - `Shared`: common models, formatting, utilities, UI components.

## Module boundaries
- Features do not import each other’s internals.
- Cross-feature coordination via:
  - shared domain models
  - repositories/services in `Data`/`Infrastructure`
  - app-level coordinator state.

## Folder structure
- `ReCon/Sources/App`
- `ReCon/Sources/Features/*`
- `ReCon/Sources/Data/*`
- `ReCon/Sources/Infrastructure/*`
- `ReCon/Sources/Shared/*`
- `ReCon/Tests/*`

## Dependency rules
- `Features -> Shared, Data`
- `Data -> Shared, Infrastructure`
- `Infrastructure -> Shared`
- `App -> all`
- No reverse imports.

## State flow rules
- `@MainActor` observable stores own UI state.
- Async work isolated in services/repositories.
- Stores invoke use-case methods and update view state deterministically.
- Side-effects (notifications, keychain, websocket IO) isolated from SwiftUI views.

## Networking strategy
- `URLSession` async/await for REST.
- Central API client applies auth headers and maps status errors.
- Backend contract preserved exactly (paths, headers, payload fields).

## Realtime strategy
- Hub client over `URLSessionWebSocketTask`.
- SignalR framing parity with `\u001e` terminator.
- Invocation IDs and response handler map.
- Reconnect backoff parity: `0,5,10,20,60` seconds.

## Persistence strategy
- Keychain for credentials and sensitive auth values.
- `UserDefaults` for simple preferences (theme, session filters, dismissed version).
- App-local cache repository for friends/messages (v1 in-memory + pluggable persistent backend, target SwiftData).

## Error handling strategy
- Typed `AppError` domain with user-facing message mapping.
- API error mapping mirrors Flutter behavior for 400/403/404/429/500 and unknown cases.
- Stores expose friendly error state + retry actions.

## Logging/debug strategy
- Unified `Logger` wrappers with category tags (`API`, `Hub`, `Auth`, `Messaging`, etc.).
- Debug-only verbose payload logging redacted for secrets.

## Testing strategy
- Unit tests first for deterministic logic:
  - auth lifecycle
  - formatter parsing
  - filter/sort logic
  - store state transitions
- Integration tests for API/hub with mock URLProtocol and websocket fakes.
- UI smoke tests for auth and tab navigation.

## Build configuration strategy
- iOS target: 18.0.
- Config files:
  - `Config/Base.xcconfig`
  - `Config/Debug.xcconfig`
  - `Config/Release.xcconfig`
- Runtime non-secret values in `Environment.plist` loaded at bootstrap.

## Security/privacy strategy
- No hardcoded secrets.
- Tokens/passwords only in Keychain.
- Minimal permission prompts, request only on user action.
- Notification permission asked in context.
- Signing/team/provision placeholders documented.

## Rationale for major choices
- SwiftUI + Observation gives concise, maintainable iOS 18-native UI/state.
- URLSession + native websocket minimizes third-party risk and improves debuggability.
- Layer boundaries reduce coupling and preserve long-term maintainability during parity work.
- Parallel app strategy avoids destabilizing current Flutter release paths.
