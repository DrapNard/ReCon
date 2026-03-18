# Flutter to iOS Feature Parity Checklist

Legend:
- `[ ]` not started
- `[/]` in progress
- `[x]` implemented
- `[~]` intentionally deferred/disabled parity

## App bootstrap
- [x] Native project scaffold (`ios-native`)
- [x] Environment/config loading
- [x] Auth-gated root flow
- [ ] Update check against GitHub release API
- [ ] Logout-triggered full app state reset parity

## Authentication
- [x] Username/email + password login request
- [x] TOTP-required response handling (`403` body `TOTP`)
- [x] Keychain persistence for auth/session credentials
- [x] Cached session revalidation (`PATCH /userSessions`)
- [x] Fallback password relogin on expired token
- [ ] Explicit session extend action parity

## App shell/navigation
- [x] Tab shell (Chat/Sessions/Worlds/Inventory/Settings)
- [x] Per-tab navigation stacks
- [ ] Screen-by-screen route parity for all push/sheet paths

## Friends and messaging
- [x] Friends list basic rendering
- [x] Friend search (`GET /users?name=`)
- [ ] Add/remove contact operations parity
- [x] Open chat detail from friend
- [x] Text message sending via hub
- [x] Hub receive/send/read event handling baseline
- [ ] Message pagination/older-message behavior parity
- [ ] Unread safeguard timer parity
- [ ] Status heartbeat parity

## Message content types
- [x] Text messages
- [ ] Audio clip messages with native player/cache parity
- [ ] Session invite messages
- [ ] Invite request messages
- [ ] Object/asset messages with preview/detail parity

## Notifications
- [x] Notification permission request capability
- [x] Local notification dispatch for unread messages
- [ ] Grouping/presentation parity per sender/content

## Sessions
- [x] Session list fetch + display
- [x] Session filter model + request mapping baseline
- [ ] Full filter UI parity
- [x] Session detail fetch + display baseline
- [ ] Session user list and all detail fields parity
- [ ] Panorama preview parity

## Worlds
- [x] World search/list fetch
- [x] World card/list rendering baseline
- [x] World detail baseline
- [ ] World sort/query controls parity
- [ ] Share action parity (`resrec:///`)

## Inventory
- [x] Inventory root and navigation baseline
- [ ] Breadcrumb navigation parity
- [ ] Sorting controls parity
- [ ] Selection mode parity
- [ ] Delete selected records parity
- [ ] Download selected assets/thumbnails parity
- [ ] Share selected record URI parity

## Profile and settings
- [x] Theme mode preference persistence
- [x] Sign out action
- [x] About link/open URL baseline
- [ ] Full profile dialog parity (supporter metadata fields)
- [x] Storage quota fetch/display baseline
- [ ] Online status selection menu parity

## Media/file capabilities
- [ ] Camera image capture parity
- [ ] Photo library pick parity
- [ ] Document picker parity
- [~] Microphone record flow parity (currently disabled in Flutter UI)

## Rich text and formatting
- [x] Rich text parser baseline (`b`, `i`, `u`, `s`, `br`, `color`, `mark`, `size`)
- [ ] Full tag compatibility parity with Flutter formatter

## Persistence
- [x] Keychain store for secrets/tokens
- [x] `UserDefaults` for lightweight settings
- [ ] Local cache parity for contacts/messages (SwiftData/SQLite final schema)

## Error/loading/offline states
- [x] Basic loading states for key views
- [x] Basic error surface for key network flows
- [ ] Offline/retry behavior parity across all screens

## Accessibility and appearance
- [x] Light/dark support
- [x] Dynamic type baseline
- [ ] VoiceOver labels/traits coverage across all interactive components

## Testing
- [x] Unit tests for auth service and formatter basics
- [ ] Unit tests for stores and filter/sort logic
- [ ] Integration tests for hub and upload pipeline
- [ ] UI smoke tests for critical user journeys

## CI/CD
- [ ] Add native iOS simulator build/test workflow
- [ ] Keep existing Flutter release workflow intact

## Deferred / intentional gaps (tracked)
- [~] Message composer attachment and mic actions remain intentionally disabled if Flutter path is disabled in current code.
