import SwiftUI

struct WorldsView: View {
    @ObservedObject var app: AppContainer
    @State private var worlds: [WorldRecord] = []
    @State private var selectedWorldTarget: WorldNavigationTarget?
    @State private var activeSessionCountByWorldId: [String: Int] = [:]
    @State private var sessionNamesByWorldId: [String: [String]] = [:]
    @State private var searchQuery = ""
    @State private var loading = false
    @State private var errorText: String?

    var body: some View {
        List(filteredWorlds) { world in
            Button {
                selectedWorldTarget = WorldNavigationTarget(world: world)
            } label: {
                DynamicTintedRow(urlString: world.thumbnailUri, environment: app.environment) {
                    HStack(spacing: 10) {
                        SharedThumbnailView(urlString: world.thumbnailUri, environment: app.environment, size: 44, fallbackSystemName: "globe")
                        VStack(alignment: .leading, spacing: 6) {
                            Text(RichTextFormatter.toAttributedString(world.name))
                                .lineLimit(2)
                            Text("Author: \(world.ownerId)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Active Sessions: \(activeSessionCountByWorldId[world.id] ?? 0)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !world.description.isEmpty {
                                Text(RichTextFormatter.toAttributedString(world.description))
                                    .lineLimit(1)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .overlay {
            if loading { ProgressView() }
            if filteredWorlds.isEmpty, !loading {
                ContentUnavailableView(
                    "No worlds found",
                    systemImage: "globe",
                    description: Text(searchQuery.isEmpty ? "No worlds available right now." : "Try another search.")
                )
            }
        }
        .searchable(text: $searchQuery, prompt: "Search worlds, tags, sessions")
        .reconListScreen(backdrop: .worlds)
        .navigationTitle("Worlds")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: searchQuery) { await load(for: searchQuery) }
        .onChange(of: app.pendingWorldOpenInWorldsTab?.id) { _, _ in
            consumePendingWorldOpen()
        }
        .refreshable { await load(for: searchQuery, debounce: false) }
        .navigationDestination(item: $selectedWorldTarget) { target in
            WorldDetailView(app: app, world: target.world, environment: app.environment)
        }
        .safeAreaInset(edge: .bottom) {
            if let errorText {
                Text(errorText).foregroundStyle(.red).padding(8)
            }
        }
    }

    private var filteredWorlds: [WorldRecord] {
        let q = normalizedName(searchQuery)
        guard !q.isEmpty else { return worlds }
        return worlds.filter { world in
            let worldName = normalizedName(world.name)
            let owner = normalizedName(world.ownerId)
            let description = normalizedName(world.description)
            let tags = normalizedName(extractedTagsText(from: world))
            let sessionNames = normalizedName((sessionNamesByWorldId[world.id] ?? []).joined(separator: " "))
            return worldName.contains(q) || owner.contains(q) || description.contains(q) || tags.contains(q) || sessionNames.contains(q)
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
            let fetchedWorlds: [WorldRecord]
            let sessions: [Session]

            if trimmedQuery.isEmpty {
                async let worldsTask = app.repository.fetchWorlds(auth: app.auth, offset: 0, limit: 256)
                async let sessionsTask = app.repository.fetchSessions(auth: app.auth)
                fetchedWorlds = try await worldsTask
                sessions = (try? await sessionsTask) ?? []
            } else {
                async let worldsTask = app.repository.searchWorlds(auth: app.auth, query: trimmedQuery, offset: 0, limit: 256)
                async let sessionsTask = app.repository.searchSessions(auth: app.auth, query: trimmedQuery)
                fetchedWorlds = try await worldsTask
                sessions = (try? await sessionsTask) ?? []
            }

            worlds = fetchedWorlds
            activeSessionCountByWorldId = makeActiveSessionMap(worlds: fetchedWorlds, sessions: sessions)
            sessionNamesByWorldId = makeSessionNamesByWorldMap(worlds: fetchedWorlds, sessions: sessions)
            errorText = nil
            consumePendingWorldOpen()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func consumePendingWorldOpen() {
        guard let target = app.pendingWorldOpenInWorldsTab else { return }
        // Ensure the destination row is visible and selectable even if a previous filter is active.
        searchQuery = ""
        if !worlds.contains(where: { $0.id == target.id }) {
            worlds.insert(target, at: 0)
        }
        selectedWorldTarget = WorldNavigationTarget(world: target)
        app.pendingWorldOpenInWorldsTab = nil
    }

    private func makeActiveSessionMap(worlds: [WorldRecord], sessions: [Session]) -> [String: Int] {
        var result: [String: Int] = [:]
        let worldKeys: [(id: String, key: String)] = worlds.map { world in
            (world.id, normalizedName(world.name))
        }

        for (id, key) in worldKeys {
            guard !key.isEmpty else {
                result[id] = 0
                continue
            }

            let count = sessions.reduce(into: 0) { partial, session in
                let sessionName = normalizedName(session.name)
                if sessionName.contains(key) || key.contains(sessionName) {
                    partial += 1
                }
            }
            result[id] = count
        }
        return result
    }

    private func makeSessionNamesByWorldMap(worlds: [WorldRecord], sessions: [Session]) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for world in worlds {
            let key = normalizedName(world.name)
            guard !key.isEmpty else {
                result[world.id] = []
                continue
            }
            let names = sessions.compactMap { session -> String? in
                let sessionName = normalizedName(session.name)
                guard sessionName.contains(key) || key.contains(sessionName) else { return nil }
                return session.name
            }
            result[world.id] = Array(Set(names)).sorted()
        }
        return result
    }

    private func extractedTagsText(from world: WorldRecord) -> String {
        let combined = "\(world.name) \(world.description)"
        let regex = try? NSRegularExpression(pattern: "(#[\\p{L}\\p{N}_-]+|\\[[^\\]]+\\])")
        let range = NSRange(location: 0, length: (combined as NSString).length)
        let matches = regex?.matches(in: combined, options: [], range: range) ?? []
        let rawTags = matches.map { (combined as NSString).substring(with: $0.range) }
        return rawTags.joined(separator: " ")
    }

    private func normalizedName(_ raw: String) -> String {
        let stripped = raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return stripped
            .replacingOccurrences(of: "[\\[\\]#]", with: " ", options: .regularExpression)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct WorldNavigationTarget: Identifiable, Hashable {
    var id: String { world.id }
    let world: WorldRecord

    static func == (lhs: WorldNavigationTarget, rhs: WorldNavigationTarget) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct WorldDetailView: View {
    @ObservedObject var app: AppContainer
    let world: WorldRecord
    let environment: AppEnvironment
    @Environment(\.openURL) private var openURL
    @State private var accent: Color = .purple
    @State private var ownerUser: RemoteUser?
    @State private var activeSessions: [Session] = []
    @State private var openError: String?

    var body: some View {
        List {
            VStack(alignment: .leading, spacing: 10) {
                Text(RichTextFormatter.toAttributedString(world.name))
                    .font(.title3.weight(.semibold))
                WorldHeroImage(urlString: world.thumbnailUri, environment: environment)
                Text(RichTextFormatter.toAttributedString(world.description.isEmpty ? "No description" : world.description))
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
                Text("ID: \(world.id)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    app.beginInventoryWorldSave(world)
                } label: {
                    Label("Save To Inventory", systemImage: "star.circle")
                }
                .buttonStyle(.borderedProminent)
            }
            .reconRowCard()
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            NavigationLink {
                SessionUserProfileView(
                    app: app,
                    userId: world.ownerId,
                    fallbackUsername: ownerUser?.username ?? world.ownerId,
                    initialUser: ownerUser,
                    initialContactStatus: "none"
                )
            } label: {
                DynamicTintedRow(
                    urlString: ownerUser?.profile?.iconUrl ?? world.ownerId,
                    environment: environment,
                    fallback: .purple
                ) {
                    HStack(spacing: 10) {
                        ProfileAvatarView(
                            username: ownerUser?.username ?? world.ownerId,
                            iconUrl: ownerUser?.profile?.iconUrl,
                            environment: environment,
                            size: 42
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ownerUser?.username ?? world.ownerId)
                                .lineLimit(1)
                            Text("World Author")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            if activeSessions.isEmpty {
                DynamicTintedRow(urlString: world.thumbnailUri, environment: environment, fallback: .purple) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Instance Detail")
                            .font(.headline)
                        Text("No active instance found for this world right now.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                ForEach(activeSessions.prefix(3)) { session in
                    DynamicTintedRow(urlString: session.thumbnailUrl, environment: environment, fallback: .purple) {
                        VStack(alignment: .leading, spacing: 10) {
                            WorldHeroImage(urlString: session.thumbnailUrl, environment: environment)
                            Text(RichTextFormatter.toAttributedString(session.name))
                                .lineLimit(2)
                            Text("\(session.joinedUsers)/\(session.maxUsers) Online")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            NavigationLink {
                                SessionDetailView(app: app, sessionID: session.id)
                            } label: {
                                Label("Instance Detail", systemImage: "arrow.right.circle")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .reconListScreen(backdrop: .worlds, accent: accent)
        .navigationTitle("World")
        .task {
            let thumbKey = world.thumbnailUri.trimmingCharacters(in: .whitespacesAndNewlines)
            let tintKey = thumbKey.isEmpty ? world.id : thumbKey
            accent = StableTintPalette.color(for: tintKey, fallback: .purple)
            ownerUser = try? await app.repository.fetchUser(auth: app.auth, userId: world.ownerId)
            activeSessions = await resolveSessionsForWorld()
            openError = nil
        }
        .safeAreaInset(edge: .bottom) {
            if let openError {
                Text(openError)
                    .foregroundStyle(.red)
                    .padding(8)
            }
        }
    }

    private func resolveSessionsForWorld() async -> [Session] {
        guard app.auth.isAuthenticated else { return [] }
        guard let sessions = try? await app.repository.fetchSessions(auth: app.auth) else { return [] }
        let worldName = normalizedName(world.name)
        let worldThumbKey = mediaKey(from: world.thumbnailUri)

        return sessions.filter { session in
            let sessionName = normalizedName(session.name)
            let byName = !worldName.isEmpty && (sessionName.contains(worldName) || worldName.contains(sessionName))
            let byThumb = !worldThumbKey.isEmpty && mediaKey(from: session.thumbnailUrl) == worldThumbKey
            return byName || byThumb
        }
        .sorted { $0.joinedUsers > $1.joinedUsers }
    }

    private func normalizedName(_ raw: String) -> String {
        let stripped = raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let basic = stripped.replacingOccurrences(of: "[^A-Za-z0-9 ]", with: " ", options: .regularExpression)
        return basic
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
}

private struct WorldHeroImage: View {
    let urlString: String
    let environment: AppEnvironment

    var body: some View {
        PanoramaHeroImageView(
            urlString: urlString,
            environment: environment,
            height: 150,
            fallbackSystemName: "photo"
        )
    }
}

struct PanoramaHeroImageView: View {
    let urlString: String
    let environment: AppEnvironment
    let height: CGFloat
    let fallbackSystemName: String

    @State private var steadyOffset: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var startedAt = Date()
    @State private var autoResumeAt = Date()

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.gray.opacity(0.2))
            .overlay {
                Image(systemName: fallbackSystemName)
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
            }
    }

    var body: some View {
        let corner = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Group {
            if let url = AssetURLResolver.resolveImageURL(urlString, environment: environment) {
                TimelineView(.animation) { context in
                    GeometryReader { geo in
                        let width = max(geo.size.width, 1)
                        let imageWidth = width * 2.35
                        let travel = max((imageWidth - width) / 2, 1)
                        let t = context.date.timeIntervalSince(startedAt)
                        let resumeProgress = max(0, min(1, context.date.timeIntervalSince(autoResumeAt) / 0.9))
                        let autoGain = isDragging ? 0 : CGFloat(resumeProgress * resumeProgress)
                        let auto = CGFloat(sin(t * 0.28)) * (travel * 0.88) * autoGain
                        let totalOffset = min(max(steadyOffset + dragOffset + auto, -travel), travel)

                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            default:
                                placeholder
                            }
                        }
                        .frame(width: imageWidth, height: height)
                        .offset(x: totalOffset)
                        .frame(width: width, height: height, alignment: .center)
                    }
                }
            } else {
                placeholder
                    .frame(height: height)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .contentShape(corner)
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    isDragging = true
                    let target = value.translation.width
                    dragOffset = (dragOffset * 0.68) + (target * 0.32)
                }
                .onEnded { value in
                    let inertia = value.predictedEndTranslation.width * 0.22
                    let target = max(min(steadyOffset + value.translation.width + inertia, 280), -280)
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                        steadyOffset = target
                        dragOffset = 0
                    }
                    isDragging = false
                    autoResumeAt = Date().addingTimeInterval(0.28)
                }
        )
        .clipShape(corner)
        .overlay {
            corner.strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
        .onAppear {
            startedAt = Date()
            autoResumeAt = Date()
        }
    }
}

private struct ProfileAvatarView: View {
    let username: String
    let iconUrl: String?
    let environment: AppEnvironment
    let size: CGFloat

    var body: some View {
        if let iconUrl, !iconUrl.isEmpty, let url = AssetURLResolver.resolveImageURL(iconUrl, environment: environment) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
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
            .fill(.gray.opacity(0.25))
            .frame(width: size, height: size)
            .overlay {
                Text(String(username.prefix(1)).uppercased())
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
    }
}
