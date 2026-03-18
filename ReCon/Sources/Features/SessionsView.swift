import SwiftUI

struct SessionsView: View {
    @ObservedObject var app: AppContainer
    @State private var sessions: [Session] = []
    @State private var worldNameBySessionID: [String: String] = [:]
    @State private var searchQuery = ""
    @State private var loading = false
    @State private var errorText: String?
    @State private var selectedSessionTarget: SessionNavigationTarget?

    var body: some View {
        List {
            if let errorText {
                Text(errorText)
                    .foregroundStyle(.red)
                    .reconRowCard()
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            ForEach(filteredSessions) { session in
                NavigationLink {
                    SessionDetailView(app: app, sessionID: session.id)
                } label: {
                    DynamicTintedRow(urlString: session.thumbnailUrl, environment: app.environment) {
                        HStack(spacing: 10) {
                            SharedThumbnailView(urlString: session.thumbnailUrl, environment: app.environment, size: 44, fallbackSystemName: "person.3")
                            VStack(alignment: .leading, spacing: 6) {
                                Text(RichTextFormatter.toAttributedString(session.name))
                                    .lineLimit(2)
                                Text("\(session.joinedUsers)/\(session.maxUsers) Online")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let worldName = worldNameBySessionID[session.id], !worldName.isEmpty {
                                    Text("World: \(worldName)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                if !session.sessionUsers.isEmpty {
                                    Text(session.sessionUsers.prefix(4).map(\.username).joined(separator: ", "))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .overlay {
            if loading {
                ProgressView()
            } else if filteredSessions.isEmpty {
                ContentUnavailableView(
                    "No sessions found",
                    systemImage: "person.3",
                    description: Text(searchQuery.isEmpty ? "No active sessions right now." : "Try another search.")
                )
            }
        }
        .searchable(text: $searchQuery, prompt: "Search sessions, users, worlds")
        .reconListScreen(backdrop: .sessions)
        .navigationTitle("Sessions")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: searchQuery) { await load(for: searchQuery) }
        .onChange(of: app.pendingSessionOpenInSessionsTab) { _, _ in
            consumePendingSessionOpen()
        }
        .refreshable { await load(for: searchQuery, debounce: false) }
        .navigationDestination(item: $selectedSessionTarget) { target in
            SessionDetailView(app: app, sessionID: target.sessionID)
        }
    }

    private var filteredSessions: [Session] {
        let q = normalizedSearchText(searchQuery)
        guard !q.isEmpty else { return sessions }
        return sessions.filter { session in
            let sessionName = normalizedSearchText(session.name)
            let host = normalizedSearchText(session.hostUsername)
            let usernames = normalizedSearchText(session.sessionUsers.map(\.username).joined(separator: " "))
            let worldName = normalizedSearchText(worldNameBySessionID[session.id] ?? "")
            return sessionName.contains(q) || host.contains(q) || usernames.contains(q) || worldName.contains(q)
        }
    }

    private func load(for query: String, debounce: Bool = true) async {
        guard app.auth.isAuthenticated else { return }
        if debounce {
            try? await Task.sleep(nanoseconds: 320_000_000)
            if Task.isCancelled { return }
        }
        loading = true
        defer { loading = false }

        do {
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let fetched: [Session]
            let worlds: [WorldRecord]

            if trimmedQuery.isEmpty {
                async let sessionsTask = app.repository.fetchSessions(auth: app.auth)
                async let worldsTask = app.repository.fetchWorlds(auth: app.auth, offset: 0, limit: 80)
                fetched = try await sessionsTask
                worlds = (try? await worldsTask) ?? []
            } else {
                async let sessionsTask = app.repository.searchSessions(auth: app.auth, query: trimmedQuery)
                async let worldsTask = app.repository.searchWorlds(auth: app.auth, query: trimmedQuery, offset: 0, limit: 80)
                fetched = try await sessionsTask
                worlds = (try? await worldsTask) ?? []
            }

            sessions = fetched.sorted {
                if $0.joinedUsers == $1.joinedUsers {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.joinedUsers > $1.joinedUsers
            }
            app.cacheWorldLookupRecords(worlds)
            worldNameBySessionID = buildWorldNameMap(sessions: sessions, worlds: worlds)
            app.cacheSessionWorldHints(buildWorldMatchMap(sessions: sessions, worlds: worlds))
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func buildWorldNameMap(sessions: [Session], worlds: [WorldRecord]) -> [String: String] {
        guard !sessions.isEmpty, !worlds.isEmpty else { return [:] }
        return sessions.reduce(into: [String: String]()) { partial, session in
            let mapped = bestMatchWorld(for: session, worlds: worlds)
            if let mapped {
                partial[session.id] = mapped.name
            }
        }
    }

    private func buildWorldMatchMap(sessions: [Session], worlds: [WorldRecord]) -> [String: WorldRecord] {
        guard !sessions.isEmpty, !worlds.isEmpty else { return [:] }
        return sessions.reduce(into: [String: WorldRecord]()) { partial, session in
            if let mapped = bestMatchWorld(for: session, worlds: worlds) {
                partial[session.id] = mapped
            }
        }
    }

    private func bestMatchWorld(for session: Session, worlds: [WorldRecord]) -> WorldRecord? {
        let sessionName = normalizedSearchText(session.name)
        let sessionThumbKey = mediaKey(from: session.thumbnailUrl)

        var best: (score: Double, world: WorldRecord)?
        for world in worlds {
            let s = score(world, sessionName: sessionName, sessionThumbKey: sessionThumbKey)
            if let best, s <= best.score { continue }
            best = (s, world)
        }

        guard let best else { return nil }
        // Prevent random first-item mapping when confidence is too low.
        return best.score >= 0.26 ? best.world : nil
    }

    private func score(_ world: WorldRecord, sessionName: String, sessionThumbKey: String) -> Double {
        let nameScore = nameMatchScore(lhs: normalizedSearchText(world.name), rhs: sessionName)
        let thumbScore: Double
        if sessionThumbKey.isEmpty {
            thumbScore = 0
        } else {
            thumbScore = mediaKey(from: world.thumbnailUri) == sessionThumbKey ? 1 : 0
        }
        return thumbScore * 0.72 + nameScore * 0.28
    }

    private func nameMatchScore(lhs: String, rhs: String) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        if lhs == rhs { return 1 }
        if lhs.contains(rhs) || rhs.contains(lhs) { return 0.75 }
        let lhsTokens = Set(lhs.split(separator: " ").map(String.init).filter { $0.count > 2 })
        let rhsTokens = Set(rhs.split(separator: " ").map(String.init).filter { $0.count > 2 })
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return 0 }
        let intersection = lhsTokens.intersection(rhsTokens).count
        let union = lhsTokens.union(rhsTokens).count
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }

    private func mediaKey(from raw: String) -> String {
        guard !raw.isEmpty else { return "" }
        let lower = raw.lowercased()
        if let hashRange = lower.range(of: "[a-f0-9]{24,128}", options: .regularExpression) {
            return String(lower[hashRange])
        }
        let pathComponent = URL(string: raw)?.lastPathComponent ?? raw.components(separatedBy: "/").last ?? raw
        return pathComponent
            .replacingOccurrences(of: "\\.[a-z0-9]+$", with: "", options: .regularExpression)
            .lowercased()
    }

    private func normalizedSearchText(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[\\[\\]#]", with: " ", options: .regularExpression)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func consumePendingSessionOpen() {
        guard let sessionID = app.pendingSessionOpenInSessionsTab, !sessionID.isEmpty else { return }
        selectedSessionTarget = SessionNavigationTarget(sessionID: sessionID)
        app.pendingSessionOpenInSessionsTab = nil
    }
}

private struct SessionNavigationTarget: Identifiable, Hashable {
    var id: String { sessionID }
    let sessionID: String
}

struct SessionDetailView: View {
    @ObservedObject var app: AppContainer
    let sessionID: String
    @Environment(\.openURL) private var openURL

    @State private var session: Session?
    @State private var relatedWorld: WorldRecord?
    @State private var userProfiles: [String: RemoteUser] = [:]
    @State private var errorText: String?
    @State private var detailAccent: Color = .green
    @State private var loadingRelatedWorld = false
    @State private var loadingProfiles = false

    var body: some View {
        ZStack {
            ReConBackdrop(style: .sessions)
                .overlay(
                    LinearGradient(
                        colors: [detailAccent.opacity(0.46), detailAccent.opacity(0.20), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .ignoresSafeArea()

            Group {
                if let session {
                    List {
                        DynamicTintedRow(
                            urlString: resolvedSessionCardTintKey(for: session),
                            environment: app.environment,
                            fallback: .green
                        ) {
                            VStack(alignment: .leading, spacing: 12) {
                                SessionHeroImage(urlString: session.thumbnailUrl, environment: app.environment)

                                Text(RichTextFormatter.toAttributedString(session.name))
                                    .font(.title3.weight(.semibold))
                                Text("Host: \(session.hostUsername)")
                                    .foregroundStyle(.secondary)
                                Text("Users: \(session.joinedUsers)/\(session.maxUsers)")
                                    .font(.headline)
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                        DynamicTintedRow(
                            urlString: relatedWorld?.thumbnailUri ?? resolvedSessionCardTintKey(for: session),
                            environment: app.environment,
                            fallback: .green
                        ) {
                            if let relatedWorld {
                                Button {
                                    app.openWorldInWorldsTab(relatedWorld)
                                } label: {
                                    HStack(spacing: 10) {
                                        SharedThumbnailView(
                                            urlString: relatedWorld.thumbnailUri,
                                            environment: app.environment,
                                            size: 42,
                                            fallbackSystemName: "globe"
                                        )
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Original World")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(RichTextFormatter.toAttributedString(relatedWorld.name))
                                                .lineLimit(2)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "arrow.right.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "globe")
                                            .foregroundStyle(.secondary)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Original World")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text("No linked world record found.")
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                    if loadingRelatedWorld {
                                        HStack(spacing: 8) {
                                            ProgressView()
                                                .controlSize(.small)
                                            Text("Looking up linked world...")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    if let instanceURL = session.sessionURLs.first(where: { URL(string: $0) != nil }) {
                                        Button {
                                            if let url = URL(string: instanceURL) {
                                                openURL(url)
                                            }
                                        } label: {
                                            Label("Open Instance", systemImage: "arrow.up.right.square")
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                        if session.sessionUsers.isEmpty {
                            Text("No players listed for this session.")
                                .foregroundStyle(.secondary)
                                .reconRowCard()
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        } else {
                            if loadingProfiles {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Loading user profiles...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .reconRowCard()
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                            ForEach(sortedUsers(session.sessionUsers, hostUsername: session.hostUsername), id: \.id) { user in
                                let isHostUser = isHost(user: user, hostUsername: session.hostUsername)
                                NavigationLink {
                                    SessionUserProfileView(
                                        app: app,
                                        userId: user.id,
                                        fallbackUsername: user.username,
                                        initialUser: userProfiles[user.id],
                                        initialContactStatus: "none"
                                    )
                                } label: {
                                    DynamicTintedRow(
                                        urlString: resolvedPlayerTintKey(for: user),
                                        environment: app.environment,
                                        fallback: .green
                                    ) {
                                        SessionUserRow(
                                            user: user,
                                            profile: userProfiles[user.id],
                                            onlineStatus: app.effectiveStatus(for: user.id, fallback: user.isPresent ? "online" : "offline"),
                                            isHost: isHostUser,
                                            environment: app.environment
                                        )
                                    }
                                }
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                } else if let errorText {
                    Text(errorText)
                        .foregroundStyle(.red)
                } else {
                    ProgressView()
                }
            }
        }
        .navigationTitle("Session")
        .task { await load() }
    }

    private func sortedUsers(_ users: [SessionUser], hostUsername: String) -> [SessionUser] {
        users.sorted {
            let lhsHost = isHost(user: $0, hostUsername: hostUsername)
            let rhsHost = isHost(user: $1, hostUsername: hostUsername)
            if lhsHost != rhsHost { return lhsHost && !rhsHost }
            if $0.isPresent != $1.isPresent { return $0.isPresent && !$1.isPresent }
            return $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending
        }
    }

    private func isHost(user: SessionUser, hostUsername: String) -> Bool {
        normalizedDisplayName(user.username) == normalizedDisplayName(hostUsername)
    }

    private func normalizedDisplayName(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolvedPlayerTintKey(for user: SessionUser) -> String {
        let icon = userProfiles[user.id]?.profile?.iconUrl.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return icon.isEmpty ? user.id : icon
    }

    private func resolvedSessionCardTintKey(for session: Session) -> String {
        let thumb = session.thumbnailUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return thumb.isEmpty ? session.id : thumb
    }

    private func load() async {
        do {
            let loaded = try await app.repository.fetchSession(auth: app.auth, id: sessionID)
            session = loaded
            relatedWorld = nil
            loadingRelatedWorld = true
            let thumbKey = loaded.thumbnailUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            let tintKey = thumbKey.isEmpty ? loaded.id : thumbKey
            detailAccent = StableTintPalette.color(for: tintKey, fallback: .green)
            relatedWorld = await resolveRelatedWorld(for: loaded)
            loadingRelatedWorld = false
            let ids = loaded.sessionUsers.map(\.id).filter { !$0.isEmpty }
            app.requestStatuses(for: ids)
            loadingProfiles = true
            await preloadUserProfiles(for: loaded.sessionUsers)
            loadingProfiles = false
            errorText = nil
        } catch {
            loadingRelatedWorld = false
            loadingProfiles = false
            errorText = error.localizedDescription
        }
    }

    private func resolveRelatedWorld(for session: Session) async -> WorldRecord? {
        guard app.auth.isAuthenticated else { return nil }
        let candidateId = extractWorldRecordId(from: session.sessionURLs)
        let normalizedSessionName = normalizedDisplayName(session.name)
        let sessionThumbKey = mediaKey(from: session.thumbnailUrl)
        let hinted = app.worldHint(forSessionID: session.id)
        async let searchedTask = app.repository.searchWorlds(auth: app.auth, query: session.name, offset: 0, limit: 256)
        async let cachedTask = app.worldLookupRecords(preferredQuery: session.name)
        let searched = (try? await searchedTask) ?? []
        let cached = await cachedTask
        var mergedByID: [String: WorldRecord] = [:]
        if let hinted { mergedByID[hinted.id] = hinted }
        for world in searched { mergedByID[world.id] = world }
        for world in cached { mergedByID[world.id] = world }
        let worlds = Array(mergedByID.values)
        guard !worlds.isEmpty else { return nil }

        if let candidateId {
            if let byId = worlds.first(where: { $0.id.caseInsensitiveCompare(candidateId) == .orderedSame }) {
                return byId
            }
        }

        if !sessionThumbKey.isEmpty,
           let byThumb = worlds.first(where: { mediaKey(from: $0.thumbnailUri) == sessionThumbKey }) {
            return byThumb
        }

        var best: (score: Double, world: WorldRecord)?
        for world in worlds {
            let score = nameMatchScore(lhs: normalizedSessionName, rhs: normalizedDisplayName(world.name))
            if let best, score <= best.score { continue }
            best = (score, world)
        }
        // Keep parity with session list matching but avoid false positives.
        guard let best, best.score >= 0.30 else { return nil }
        return best.world
    }

    private func extractWorldRecordId(from urls: [String]) -> String? {
        for raw in urls {
            if let match = raw.range(of: "R-[A-Za-z0-9\\-]+", options: .regularExpression) {
                return String(raw[match])
            }
        }
        return nil
    }

    private func mediaKey(from raw: String) -> String {
        guard !raw.isEmpty else { return "" }
        let lower = raw.lowercased()
        if let hashRange = lower.range(of: "[a-f0-9]{24,128}", options: .regularExpression) {
            return String(lower[hashRange])
        }
        let pathComponent = URL(string: raw)?.lastPathComponent ?? raw.components(separatedBy: "/").last ?? raw
        return pathComponent
            .replacingOccurrences(of: "\\.[a-z0-9]+$", with: "", options: .regularExpression)
            .lowercased()
    }

    private func nameMatchScore(lhs: String, rhs: String) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        if lhs == rhs { return 1 }
        if lhs.contains(rhs) || rhs.contains(lhs) { return 0.74 }
        let lhsTokens = Set(lhs.split(separator: " ").map(String.init).filter { $0.count > 2 })
        let rhsTokens = Set(rhs.split(separator: " ").map(String.init).filter { $0.count > 2 })
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return 0 }
        let intersection = lhsTokens.intersection(rhsTokens).count
        let union = lhsTokens.union(rhsTokens).count
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }

    private func preloadUserProfiles(for users: [SessionUser]) async {
        userProfiles = [:]
        let targets = Array(users.prefix(30))
        await withTaskGroup(of: (String, RemoteUser?).self) { group in
            for user in targets {
                group.addTask {
                    guard !user.id.isEmpty else { return (user.id, nil) }
                    let profile = try? await app.repository.fetchUser(auth: app.auth, userId: user.id)
                    return (user.id, profile)
                }
            }
            for await (userId, profile) in group {
                guard let profile, !userId.isEmpty else { continue }
                userProfiles[userId] = profile
            }
        }
    }
}

private struct SessionHeroImage: View {
    let urlString: String
    let environment: AppEnvironment

    var body: some View {
        PanoramaHeroImageView(
            urlString: urlString,
            environment: environment,
            height: 170,
            fallbackSystemName: "person.3"
        )
    }
}

private struct SessionUserRow: View {
    let user: SessionUser
    let profile: RemoteUser?
    let onlineStatus: String
    let isHost: Bool
    let environment: AppEnvironment

    var body: some View {
        HStack(spacing: 10) {
            SessionUserAvatarView(
                username: profile?.username ?? user.username,
                iconUrl: profile?.profile?.iconUrl,
                environment: environment,
                size: 42
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(profile?.username ?? user.username)
                        .lineLimit(1)
                    if isHost {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }

                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor(onlineStatus))
                        .frame(width: 10, height: 10)
                    Text(statusText(onlineStatus, isPresent: user.isPresent))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "sociable": return .blue
        case "online": return .green
        case "away": return .yellow
        case "busy": return .red
        default: return .gray
        }
    }

    private func statusText(_ status: String, isPresent: Bool) -> String {
        if isPresent { return "In session" }
        let normalized = status.lowercased()
        if normalized == "offline" || normalized == "invisible" { return "Offline" }
        return normalized.capitalized
    }
}

private struct SessionUserAvatarView: View {
    let username: String
    let iconUrl: String?
    let environment: AppEnvironment
    let size: CGFloat

    var body: some View {
        if let iconUrl, let url = AssetURLResolver.resolveImageURL(iconUrl, environment: environment) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                placeholder
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Circle()
            .fill(.white.opacity(0.16))
            .frame(width: size, height: size)
            .overlay {
                Text(String(username.prefix(1)).uppercased())
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
            }
    }
}

struct SessionGreenBackdrop: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.03, green: 0.14, blue: 0.12),
                        Color(red: 0.05, green: 0.22, blue: 0.17),
                        Color(red: 0.08, green: 0.28, blue: 0.20)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}
