# Flutter to Native iOS Audit

## 1. High-level app summary
- Product: **ReCon**, a Resonite companion app focused on contacts, chat, sessions, worlds, and inventory workflows.
- Current implementation: Flutter multi-platform app, with Android as most complete target and partial desktop/iOS support.
- Current backend model:
  - REST API at `https://api.resonite.com`
  - Asset host at `https://assets.resonite.com`
  - Hub websocket endpoint via `https://api.resonite.com/hub` upgraded to `wss://.../hub`

## 2. Product purpose inferred from code
- Sign in with Resonite credentials (username/email + password + optional 2FA code).
- View and interact with friend list, presence state, and direct messages.
- Browse public sessions and worlds.
- Browse and manage inventory records (select, delete, share/download).
- View account profile, storage quota, and app settings.

## 3. Feature inventory by module/screen

### App shell
- Startup initializes secure settings, attempts cached auth refresh, and decides auth gate.
- Themed app with light/dark and dynamic color support.
- Optional update notifier against GitHub latest release tag.

### Auth
- Login form with username/email, password, optional TOTP.
- Cached auth revalidation and password fallback login.
- Session extension and logout.

### Chat / Friends
- Friends list with statuses, unread counts, search filter.
- Presence/status controls (sociable/online/busy/invisible).
- User search + add contact.
- Chat detail per friend.
- Realtime events via hub:
  - receive message
  - sent confirmation
  - messages read
  - status updates
  - session updates/removals

### Messaging
- Message types: text, sound, session invite, object(asset), invite request.
- Rich text formatter for Resonite tags.
- Unread tracking and local notifications.
- Message cache with load/reload semantics.

### Sessions
- Session grid list, pull-to-refresh, filter dialog.
- Session details including users list and 360 preview (panorama widget).

### Worlds
- World records paged search.
- World grid list and detail screen.
- Share world `resrec:///owner/id` URI.

### Inventory
- Directory-like navigation with breadcrumb path.
- Mixed record list (paths + objects), selection mode.
- Sorting modes and direction.
- Delete selected records.
- Share asset URI.
- Download selected assets/thumbnails to directory.

### Settings/Profile
- Toggle notifications setting.
- Theme mode selection.
- Sign out.
- About + GitHub link.
- Profile dialog with account details and storage quota.

## 4. Flutter architectural analysis
- Root wiring:
  - `main.dart` manual dependency setup.
  - `ClientHolder` (`InheritedWidget`) provides `ApiClient`, `SettingsClient`, `NotificationClient`.
- State management:
  - `provider` + `ChangeNotifier` for Messaging/Session/Inventory clients.
- Data access:
  - Thin API classes under `lib/apis`.
  - `ApiClient` centralizes auth headers and HTTP wrappers.
- Realtime:
  - Custom `HubManager` over websocket with SignalR-style framing (`\u001e`).
- Local persistence:
  - `flutter_secure_storage` for auth + app settings.
  - Hive box for contact/message metadata cache.

## 5. Dependency inventory (Flutter packages)
- Networking/protocol: `http`, `web_socket_channel`, `http_parser`, `crypto`
- State/util: `provider`, `collection`, `uuid`, `intl`, `logging`
- Storage: `flutter_secure_storage`, `hive`, `hive_flutter`, `path_provider`
- UI/media: `cached_network_image`, `photo_view`, `dynamic_color`, `flutter_cube`
- Notifications/background: `flutter_local_notifications`, `workmanager`, `background_downloader`
- Device/file/media: `file_picker`, `image_picker`, `camera`, `record`, `just_audio`, `share_plus`, `permission_handler`
- Misc: `url_launcher`, `package_info_plus`, `flutter_phoenix`

## 6. Plugin replacement strategy on iOS
- `http` -> `URLSession` async/await.
- `flutter_secure_storage` -> Keychain services wrapper.
- `hive` -> SwiftData (or SQLite fallback if schema/perf demands).
- `provider/ChangeNotifier` -> Observation (`@Observable`) + `@MainActor` stores.
- `web_socket_channel` -> `URLSessionWebSocketTask` with hub protocol adapter.
- `flutter_local_notifications` -> `UserNotifications` (`UNUserNotificationCenter`).
- `background_downloader` -> `URLSession` background/download tasks.
- `cached_network_image` -> `AsyncImage` + custom image cache.
- `just_audio` -> `AVAudioPlayer` or `AVPlayer` (file-based clips).
- `record` -> `AVAudioRecorder` (v1 parity can keep disabled flow if Flutter currently disabled).
- `image_picker/camera/file_picker` -> `PHPickerViewController`, `UIImagePickerController`, `UIDocumentPickerViewController`.
- `share_plus` -> `UIActivityViewController`.
- `url_launcher` -> `openURL` / `Link`.
- `flutter_phoenix` restart behavior -> root app state reset coordinator.

## 7. Routing map (Flutter -> native)
- `MaterialApp(home: Login|Home)` -> root `NavigationStack` based on auth state.
- Home `PageView + NavigationBar` -> native `TabView` with per-tab navigation stacks.
- Push flows:
  - Friend tile -> chat detail
  - Session/world cards -> detail screens
  - Settings/Profile/UserSearch dialogs -> sheets or pushes based on iOS conventions

## 8. State map (Flutter -> Swift)
- `MessagingClient` -> `MessagingStore` (observable, main-actor).
- `SessionClient` -> `SessionsStore`.
- `InventoryClient` -> `InventoryStore`.
- `SettingsClient` -> `SettingsStore`.
- `ApiClient` -> `AuthenticatedAPIClient + AuthService`.

## 9. Data model map
- Core entities identified:
  - Auth: `AuthenticationData`
  - Messaging: `Message`, `MessageType`, `MessageState`, `MarkReadBatch`, `InviteRequest`
  - Users: `User`, `Friend`, `UserStatus`, `OnlineStatus`, `UserProfile`
  - Sessions: `Session`, `SessionMetadata`, `SessionUser`, `SessionFilterSettings`
  - Records/Inventory: `Record`, `RecordType`, `RecordId`, upload/preprocess DTOs
  - Profile: `PersonalProfile`, `StorageQuota`, entitlement/supporter hierarchies

## 10. API/service map
- Auth/session:
  - `POST /userSessions` login
  - `PATCH /userSessions` session extend/revalidate
- Users/contacts/messages:
  - `GET /users/{id}/contacts`
  - `GET /users?name=...`
  - `GET /users/{id}/messages?...`
  - hub methods: `SendMessage`, `MarkMessagesRead`, `InitializeStatus`, etc.
- Sessions:
  - `GET /sessions` (+ filters)
  - `GET /sessions/{id}`
- Records/worlds/inventory:
  - `POST /records/pagedSearch`
  - `GET /users/{id}/records?...`
  - `PUT/DELETE /users/{id}/records/{recordId}`
  - preprocess/upload chunk endpoints
- Profile/storage:
  - `GET /users/{self}`
  - `GET /users/{self}/storage`

## 11. Storage map
- Secure storage keys in Flutter:
  - `userId`, `machineId`, `token`, `password`, `uid`, plus serialized settings payload.
- Hive box `message-box`:
  - Contacts by user id.
  - Last status update timestamp.

## 12. Design system map
- Material 3 styling, dynamic colors, theme mode from settings.
- Shared visual patterns:
  - card grids for sessions/worlds/inventory
  - snackbar-based transient errors
  - inline loading (`LinearProgressIndicator`) + empty/error widgets

## 13. Asset inventory
- App logos in `assets/images` (`logo.png`, `logo-white.png`, `logo512.png`).
- Remote images mostly loaded from `resdb` transformed URLs via `Aux.resdbToHttp`.
- No custom local font files.

## 14. Localization inventory
- No localization bundles found; user-facing strings hardcoded in English.
- i18n library `intl` used mainly for date formatting and sentence casing.

## 15. Native capability inventory
- Notifications: local unread notifications.
- Background modes (iOS plist): `fetch`, `processing`.
- File/camera/audio related plugin presence; some flows currently intentionally disabled in UI.
- No evidence of:
  - in-app purchases
  - analytics SDK
  - crash reporting SDK
  - deep link/universal link handling in native delegates

## 16. Risk register
- High:
  - Hub realtime protocol parity errors causing silent message/presence regressions.
  - Complex record upload/preprocess flow parity.
  - Rich text rendering behavior differences.
- Medium:
  - Cache semantics divergence (Hive -> SwiftData/SQLite).
  - iOS permission timing differences.
  - Background download behavior differences.
- Low:
  - UI visual differences due to Material -> SwiftUI adaptation.

## 17. Complexity estimate by module
- High: Messaging realtime + message types + unread notifications.
- High: Inventory browser + asset upload/download.
- Medium: Sessions/worlds lists + detail views.
- Medium: Auth + cached login + 2FA.
- Medium: Settings/profile.
- Medium: Rich text parser.

## 18. Recommended migration order
1. App bootstrap + environment + architecture skeleton.
2. Auth + secure storage + HTTP core.
3. Tab shell + sessions/worlds read-only browsing.
4. Messaging realtime + chat UI + notifications.
5. Inventory browsing + destructive/select flows.
6. Asset upload/download/share, profile/settings completion.
7. Testing hardening + docs + CI.

## 19. Known unknowns / assumptions
- Some Flutter features are intentionally disabled (mic/attachments in message input). Literal parity keeps these disabled unless explicitly changed.
- Existing iOS runner metadata is Flutter-oriented; native app will define independent signing/config.
- No server/API changes are permitted for migration.
- iPhone-first v1 scope; iPad adaptation deferred.
