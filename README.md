# ReCon iOS Native fork

<p align="center">
<img src="https://github.com/DrapNard/ReCon/raw/main/docs/icon.png" width="512"/>
</p>

---

## Overview
- App name: `ReCon`
- Bundle identifier: `com.drapnard.recon`
- Stack: SwiftUI, async/await, URLSession, URLSessionWebSocketTask, Keychain, UserDefaults
- Minimum target: iOS 18

## Project layout
- Xcode project: `ReCon.xcodeproj`
- App target sources: `ReCon/Sources`
- App resources: `ReCon/Resources`
- Tests: `ReCon/Tests`
- Widget extension: `ReConWidget`

## Run in Xcode
1. Open `ReCon.xcodeproj`.
2. Select the `ReCon` scheme.
3. Choose a simulator or device.
4. Build and Run.

## CLI build (no signing)
```bash
xcodebuild \
  -project ReCon.xcodeproj \
  -scheme ReCon \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Environment configuration
File:
- `ReCon/Resources/Environment.plist`

Required keys:
- `API_BASE_URL`
- `ASSETS_BASE_URL`
- `HUB_URL`

## Testing
Run tests from Xcode (`ReCon` scheme), or with CLI:
```bash
xcodebuild \
  -project ReCon.xcodeproj \
  -scheme ReCon \
  -destination 'platform=iOS Simulator,name=iPhone 13 Pro,OS=18.0' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## Migration documentation
- Audit: `docs/migration/flutter-to-ios-audit.md`
- Feature parity checklist: `docs/migration/flutter-to-ios-feature-parity-checklist.md`
- Target architecture: `docs/architecture/ios-target-architecture.md`
- Migration plan: `docs/migration/flutter-to-native-ios-migration-plan.md`
- Gap analysis: `docs/migration/flutter-to-ios-gap-analysis.md`
- iOS setup: `docs/setup/ios-local-development.md`
- iOS test strategy: `docs/testing/ios-test-strategy.md`
- ADRs: `docs/decisions/`

## Migration status overview
Implemented baseline:
- Native iOS project scaffold.
- Auth lifecycle (login + cached login fallback).
- Core tab shell.
- Sessions/worlds/inventory/profile baseline data flows.
- Settings/theme/signout baseline.
- Hub client baseline and notification service baseline.

## Related docs
- Root migration and parity docs live in `docs/`
- Main repository README: `README.md`
