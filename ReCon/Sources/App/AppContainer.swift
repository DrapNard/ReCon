import Foundation
import Combine
#if canImport(WidgetKit)
import WidgetKit
#endif

enum AppTab: Hashable {
    case chat
    case sessions
    case worlds
    case inventory
    case settings
}

@MainActor
final class AppContainer: ObservableObject {
    private static let widgetAppGroupID = "group.com.drapnard.recon"
    private static let widgetSnapshotKey = "widget.snapshot.v1"

    let environment: AppEnvironment
    let keychain: KeychainStore
    let settingsStore: SettingsStore
    let notificationService: NotificationService
    let apiClient: APIClient
    let authService: AuthService
    let repository: ReConRepository
    let hubClient: HubClient

    @Published var auth: AuthenticationData = .unauthenticated
    @Published var startupComplete = false
    @Published var liveStatusByUserId: [String: String] = [:]
    @Published var selfOnlineStatus: String = "offline"
    @Published var contactsSnapshot: [Friend] = []
    @Published var contactsRevision: Int = 0
    @Published var selectedTab: AppTab = .chat
    @Published var pendingInventoryWorldSave: WorldRecord?
    @Published var inventoryBannerText: String?
    @Published var pendingWorldOpenInWorldsTab: WorldRecord?
    @Published var pendingSessionOpenInSessionsTab: String?
    private var contactsRefreshTask: Task<Void, Never>?
    private var widgetRefreshTask: Task<Void, Never>?
    private var worldLookupCache: [WorldRecord] = []
    private var worldLookupCacheDate: Date = .distantPast
    private var sessionWorldHints: [String: WorldRecord] = [:]

    init(environment: AppEnvironment = .load()) {
        self.environment = environment
        self.keychain = KeychainStore()
        self.settingsStore = SettingsStore()
        self.notificationService = NotificationService()
        self.apiClient = APIClient(environment: environment)
        self.authService = AuthService(api: apiClient, keychain: keychain)
        self.repository = ReConRepository(api: apiClient)
        self.hubClient = HubClient(environment: environment)
    }

    func bootstrap() async {
        let cached = await authService.tryCachedLogin()
        self.auth = cached
        self.startupComplete = true
        if cached.isAuthenticated {
            connectHub()
            await refreshSelfStatus()
            await refreshContactsSnapshot()
            await refreshWidgetSnapshot()
        } else {
            clearWidgetSnapshot()
        }
    }

    func login(username: String, password: String, totp: String?) async throws {
        let auth = try await authService.tryLogin(username: username, password: password, oneTimePad: totp)
        self.auth = auth
        connectHub()
        await refreshSelfStatus()
        await refreshContactsSnapshot()
        await refreshWidgetSnapshot()
    }

    func logout() {
        authService.logout()
        hubClient.disconnect()
        auth = .unauthenticated
        liveStatusByUserId = [:]
        selfOnlineStatus = "offline"
        contactsSnapshot = []
        contactsRevision += 1
        contactsRefreshTask?.cancel()
        widgetRefreshTask?.cancel()
        contactsRefreshTask = nil
        widgetRefreshTask = nil
        worldLookupCache = []
        worldLookupCacheDate = .distantPast
        sessionWorldHints = [:]
        clearWidgetSnapshot()
    }

    private func connectHub() {
        hubClient.setHandler("ReceiveStatusUpdate") { [weak self] args in
            guard
                let self,
                let first = args.first as? [String: Any],
                let userId = first["userId"] as? String
            else { return }

            let parsed = Self.parseStatus(first["onlineStatus"]) ?? "offline"
            Task { @MainActor in
                self.liveStatusByUserId[userId] = parsed
                if userId == self.auth.userId {
                    self.selfOnlineStatus = parsed
                }
                self.scheduleContactsRefresh()
                self.scheduleWidgetRefresh()
            }
        }
        hubClient.setHandler("ReceiveMessage") { [weak self] args in
            guard
                let self,
                let first = args.first as? [String: Any]
            else { return }
            let message = Message(map: first)
            Task { @MainActor in
                self.scheduleContactsRefresh()
                self.scheduleWidgetRefresh()
                let shouldNotify = message.recipientId == self.auth.userId && message.senderId != self.auth.userId
                if shouldNotify {
                    let senderName = (first["senderUsername"] as? String) ?? message.senderId
                    self.notificationService.showUnreadMessage(
                        sender: senderName,
                        body: self.messagePreview(from: message)
                    )
                }
            }
        }
        hubClient.connect(headers: ["Authorization": auth.authorizationHeaderValue])
        requestStatuses(for: nil)
    }

    func effectiveStatus(for userId: String, fallback: String?) -> String {
        liveStatusByUserId[userId] ?? fallback ?? "offline"
    }

    func refreshSelfStatus() async {
        guard auth.isAuthenticated else { return }
        do {
            if let status = try await repository.fetchUserStatus(auth: auth, userId: auth.userId) {
                selfOnlineStatus = status
                liveStatusByUserId[auth.userId] = status
            }
        } catch {
            // Keep existing status if server status endpoint is temporarily unavailable.
        }
    }

    func setSelfStatus(_ status: String) {
        guard auth.isAuthenticated else { return }
        let mapped = Self.statusCode(for: status)
        let now = ISO8601DateFormatter().string(from: Date())
        let payload: [String: Any] = [
            "userId": auth.userId,
            "onlineStatus": mapped,
            "lastStatusChange": now,
            "lastPresenceTimestamp": now,
            "userSessionId": UUID().uuidString,
            "currentSessionIndex": -1,
            "sessions": [],
            "appVersion": "ReCon",
            "outputDevice": "iOS",
            "isMobile": true,
            "isPresent": true,
            "compatibilityHash": "",
            "sessionType": "Chat client"
        ]
        hubClient.send(target: "BroadcastStatus", arguments: [payload, ["group": 1, "targetIds": NSNull()]])
        selfOnlineStatus = status
        liveStatusByUserId[auth.userId] = status
        requestStatuses(for: [auth.userId])
        Task { await refreshWidgetSnapshot() }
    }

    func requestStatuses(for userIds: [String]?) {
        guard auth.isAuthenticated else { return }
        let isInvisible = selfOnlineStatus == "invisible"
        if let userIds, !userIds.isEmpty {
            for userId in userIds {
                hubClient.send(target: "RequestStatus", arguments: [userId, isInvisible])
            }
        } else {
            hubClient.send(target: "RequestStatus", arguments: [NSNull(), isInvisible])
        }
    }

    func updateContact(userId: String, username: String, profileIconUrl: String?, contactStatus: String) async -> Bool {
        guard auth.isAuthenticated else { return false }

        let now = ISO8601DateFormatter().string(from: Date())
        let payload: [String: Any] = [
            "id": userId,
            "contactUsername": username,
            "ownerId": auth.userId,
            "userStatus": [
                "onlineStatus": 0,
                "lastStatusChange": now,
                "lastPresenceTimestamp": now,
                "currentSessionIndex": -1,
                "sessions": [],
                "sessionType": "Unknown",
                "appVersion": "",
                "outputDevice": "",
                "isPresent": false
            ],
            "profile": [
                "iconUrl": profileIconUrl ?? ""
            ],
            "contactStatus": contactStatus,
            "latestMessageTime": now,
            "isAccepted": contactStatus.lowercased() == "accepted"
        ]

        let result = await hubClient.sendAndWait(target: "UpdateContact", arguments: [payload])
        return (result as? Bool) ?? false
    }

    func beginInventoryWorldSave(_ world: WorldRecord) {
        selectedTab = .inventory
        pendingInventoryWorldSave = world
    }

    func finishInventoryWorldSave(message: String? = nil) {
        pendingInventoryWorldSave = nil
        inventoryBannerText = message
    }

    func openWorldInWorldsTab(_ world: WorldRecord) {
        pendingWorldOpenInWorldsTab = world
        selectedTab = .worlds
    }

    func openSessionInSessionsTab(_ sessionId: String) {
        pendingSessionOpenInSessionsTab = sessionId
        selectedTab = .sessions
    }

    func scheduleContactsRefresh(delayNanoseconds: UInt64 = 450_000_000) {
        guard auth.isAuthenticated else { return }
        contactsRefreshTask?.cancel()
        contactsRefreshTask = Task { [weak self] in
            guard let self else { return }
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            await self.refreshContactsSnapshot()
        }
    }

    func refreshContactsSnapshot() async {
        guard auth.isAuthenticated else { return }
        do {
            let contacts = try await repository.fetchContacts(auth: auth)
            contactsSnapshot = contacts
            contactsRevision += 1
            for friend in contacts {
                if let status = friend.onlineStatus, !status.isEmpty {
                    liveStatusByUserId[friend.contactUserId] = status.lowercased()
                }
            }
            await refreshWidgetSnapshot()
        } catch {
            // Keep previous snapshot to avoid wiping contacts on transient errors.
        }
    }

    func scheduleWidgetRefresh(delayNanoseconds: UInt64 = 500_000_000) {
        guard auth.isAuthenticated else { return }
        widgetRefreshTask?.cancel()
        widgetRefreshTask = Task { [weak self] in
            guard let self else { return }
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            await self.refreshWidgetSnapshot()
        }
    }

    func cacheWorldLookupRecords(_ worlds: [WorldRecord]) {
        guard !worlds.isEmpty else { return }
        var existingByID = Dictionary(uniqueKeysWithValues: worldLookupCache.map { ($0.id, $0) })
        for world in worlds {
            existingByID[world.id] = world
        }
        worldLookupCache = Array(existingByID.values)
        worldLookupCacheDate = Date()
    }

    func worldLookupRecords(preferredQuery: String?) async -> [WorldRecord] {
        guard auth.isAuthenticated else { return [] }

        let query = preferredQuery?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !query.isEmpty,
           let searched = try? await repository.searchWorlds(auth: auth, query: query, offset: 0, limit: 120),
           !searched.isEmpty {
            cacheWorldLookupRecords(searched)
            return searched
        }

        let cacheAge = Date().timeIntervalSince(worldLookupCacheDate)
        if !worldLookupCache.isEmpty, cacheAge < 180 {
            return worldLookupCache
        }

        if let fetched = try? await repository.fetchWorlds(auth: auth, offset: 0, limit: 256), !fetched.isEmpty {
            cacheWorldLookupRecords(fetched)
            return fetched
        }

        return worldLookupCache
    }

    func cacheSessionWorldHints(_ hints: [String: WorldRecord]) {
        guard !hints.isEmpty else { return }
        for (sessionID, world) in hints {
            sessionWorldHints[sessionID] = world
        }
    }

    func worldHint(forSessionID sessionID: String) -> WorldRecord? {
        sessionWorldHints[sessionID]
    }

    func refreshWidgetSnapshot() async {
        guard auth.isAuthenticated else {
            clearWidgetSnapshot()
            return
        }

        async let sessionsTask = repository.fetchSessions(auth: auth)
        async let storageTask = repository.fetchStorageQuota(auth: auth)

        var contacts = contactsSnapshot
        if contacts.isEmpty {
            contacts = (try? await repository.fetchContacts(auth: auth)) ?? []
        }
        let sessions = (try? await sessionsTask) ?? []
        let storage = (try? await storageTask)

        let onlineContacts = contacts.filter { friend in
            let status = effectiveStatus(for: friend.contactUserId, fallback: friend.onlineStatus).lowercased()
            return status == "online" || status == "sociable" || status == "away" || status == "busy"
        }.count
        let latestSession = sessions.max {
            if $0.joinedUsers == $1.joinedUsers {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending
            }
            return $0.joinedUsers < $1.joinedUsers
        }

        let payload: [String: Any] = [
            "profileStatus": selfOnlineStatus,
            "onlineContacts": onlineContacts,
            "openSessions": sessions.count,
            "storageUsedBytes": storage?.usedBytes ?? 0,
            "storageQuotaBytes": storage?.fullQuotaBytes ?? 0,
            "latestSessionName": latestSession?.name ?? "",
            "latestSessionHost": latestSession?.hostUsername ?? "",
            "latestSessionUsers": latestSession?.joinedUsers ?? 0,
            "latestSessionMaxUsers": latestSession?.maxUsers ?? 0,
            "onlineFriendNames": contacts.filter { friend in
                let status = effectiveStatus(for: friend.contactUserId, fallback: friend.onlineStatus).lowercased()
                return status == "online" || status == "sociable" || status == "away" || status == "busy"
            }.prefix(5).map(\.contactUsername),
            "lastUpdated": ISO8601DateFormatter().string(from: Date())
        ]
        persistWidgetSnapshot(payload)
    }

    private func persistWidgetSnapshot(_ payload: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            let defaults = UserDefaults(suiteName: Self.widgetAppGroupID) ?? .standard
            defaults.set(data, forKey: Self.widgetSnapshotKey)
            defaults.synchronize()
#if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
#endif
        }
    }

    private func clearWidgetSnapshot() {
        let defaults = UserDefaults(suiteName: Self.widgetAppGroupID) ?? .standard
        defaults.removeObject(forKey: Self.widgetSnapshotKey)
        defaults.synchronize()
#if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
#endif
    }

    private func messagePreview(from message: Message) -> String {
        let raw = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "New message" }
        let stripped = raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        if stripped.count <= 120 { return stripped }
        return String(stripped.prefix(117)) + "..."
    }
}

private extension AppContainer {
    static func parseStatus(_ value: Any?) -> String? {
        if let text = value as? String {
            if let idx = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return parseStatus(idx)
            }
            return text.lowercased()
        }
        if let idx = value as? Int { return parseStatus(idx) }
        return nil
    }

    static func parseStatus(_ idx: Int) -> String? {
        switch idx {
        case 0: return "offline"
        case 1: return "invisible"
        case 2: return "away"
        case 3: return "busy"
        case 4: return "online"
        case 5: return "sociable"
        default: return nil
        }
    }

    static func statusCode(for status: String) -> Int {
        switch status.lowercased() {
        case "invisible": return 1
        case "away": return 2
        case "busy": return 3
        case "online": return 4
        case "sociable": return 5
        default: return 0
        }
    }
}
