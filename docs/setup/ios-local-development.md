# iOS Local Development

## Toolchain assumptions
- Xcode: 16+
- Swift: 5.10+
- Deployment target: iOS 18.0

## Project location
- `ReCon.xcodeproj`

## Signing/config placeholders
- Use your local Apple Developer Team in target signing settings.
- Bundle identifier defaults are placeholders and may require local adjustment.

## Environment configuration
- Runtime environment file:
  - `ReCon/Resources/Environment.plist`
- Default values are non-secret and safe.
- Do not commit credentials or API secrets.

## Running on simulator/device
1. Open Xcode project.
2. Select `ReCon` scheme.
3. Choose iOS simulator/device.
4. Build and Run.

## Troubleshooting
- If auth fails immediately, verify network reachability and environment base URLs.
- If websocket events fail, inspect logs for hub framing/protocol parse errors.
- If notifications do not appear, confirm permission granted and app foreground/background state.
