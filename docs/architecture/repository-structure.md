# Repository Structure

## Top-level ownership
- `lib/`, `android/`, `ios/`, `linux/`, `windows/`, `web/`: existing Flutter app.
- `ios-native/`: new native iOS app and tests.
- `docs/`: migration, architecture, setup, testing, decision records.

## Native iOS ownership boundaries
- `ReCon/Sources/App`: app composition and startup.
- `ReCon/Sources/Features`: feature-specific UI and state.
- `ReCon/Sources/Data`: repository interfaces/implementations.
- `ReCon/Sources/Infrastructure`: transport/storage/platform services.
- `ReCon/Sources/Shared`: shared models/helpers/components.
- `ReCon/Tests`: unit/integration tests.

## Rule of change
- Feature work should primarily touch one feature folder plus shared/infrastructure abstractions.
- Cross-cutting behavior must be documented in `docs/decisions`.
