import SwiftUI

struct FriendsView: View {
    @ObservedObject var app: AppContainer
    @State private var query = ""
    @State private var friends: [Friend] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var selectedProfileTarget: ProfileTarget?

    var body: some View {
        List(filteredFriends) { friend in
            NavigationLink {
                ChatView(app: app, friend: friend)
            } label: {
                let effectiveStatus = app.effectiveStatus(for: friend.contactUserId, fallback: friend.onlineStatus)
                DynamicTintedRow(urlString: friend.profileIconUrl ?? "", environment: app.environment, fallback: .blue) {
                    HStack(spacing: 10) {
                        FriendAvatarView(friend: friend, status: effectiveStatus, size: 42, environment: app.environment)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(RichTextFormatter.toAttributedString(friend.contactUsername))
                                .lineLimit(1)
                            HStack(spacing: 8) {
                                FriendStatusDot(status: effectiveStatus)
                                Text(effectiveStatus.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(friend.latestMessageTime, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .contextMenu {
                Button("View Profile") {
                    selectedProfileTarget = ProfileTarget(
                        userId: friend.contactUserId,
                        username: friend.contactUsername,
                        contactStatus: friend.contactStatus ?? (friend.isAccepted == true ? "accepted" : "none")
                    )
                }
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .overlay {
            if loading {
                ProgressView()
            } else if filteredFriends.isEmpty {
                ContentUnavailableView(
                    "No friends found",
                    systemImage: "person.2",
                    description: Text(query.isEmpty ? "Your contact list is empty." : "Try a different name.")
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let errorText {
                Text(errorText)
                    .foregroundStyle(.red)
                    .padding(8)
            }
        }
        .searchable(text: $query, prompt: "Search friends")
        .task { await load() }
        .onChange(of: app.contactsRevision) { _, _ in
            friends = app.contactsSnapshot
        }
        .refreshable { await load() }
        .reconListScreen(backdrop: .chat)
        .navigationTitle("ReCon")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedProfileTarget) { target in
            SessionUserProfileView(
                app: app,
                userId: target.userId,
                fallbackUsername: target.username,
                initialUser: nil,
                initialContactStatus: target.contactStatus
            )
        }
    }

    private var filteredFriends: [Friend] {
        let accepted = friends.filter { friend in
            guard let contactStatus = friend.contactStatus?.lowercased() else { return true }
            return contactStatus == "accepted"
        }
        guard !query.isEmpty else {
            return accepted.sorted { $0.latestMessageTime > $1.latestMessageTime }
        }
        return accepted
            .filter { $0.contactUsername.localizedCaseInsensitiveContains(query) }
            .sorted { $0.contactUsername.count < $1.contactUsername.count }
    }

    private func load() async {
        guard app.auth.isAuthenticated else { return }
        if !app.contactsSnapshot.isEmpty {
            friends = app.contactsSnapshot
        }
        loading = true
        defer { loading = false }

        await app.refreshContactsSnapshot()
        friends = app.contactsSnapshot
        await refreshContactStatuses()
        app.requestStatuses(for: friends.map(\.contactUserId))
        errorText = nil
    }

    private func refreshContactStatuses() async {
        let ids = friends
            .filter { ($0.contactStatus?.lowercased() == "accepted") || ($0.isAccepted == true) }
            .map(\.contactUserId)
            .prefix(40)
        await withTaskGroup(of: (String, String?).self) { group in
            for userId in ids {
                group.addTask {
                    let status = try? await app.repository.fetchUserStatus(auth: app.auth, userId: userId)
                    return (userId, status)
                }
            }

            for await (userId, status) in group {
                guard let status else { continue }
                await MainActor.run {
                    app.liveStatusByUserId[userId] = status
                }
            }
        }
    }
}

private struct ProfileTarget: Hashable, Identifiable {
    var id: String { userId }
    let userId: String
    let username: String
    let contactStatus: String
}

private struct FriendAvatarView: View {
    let friend: Friend
    let status: String
    let size: CGFloat
    let environment: AppEnvironment

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let icon = friend.profileIconUrl, !icon.isEmpty {
                let resolved = AssetURLResolver.resolveImageURL(icon, environment: environment)
                if let resolved {
                    AsyncImage(url: resolved) { image in
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
            } else {
                placeholder
            }

            FriendStatusDot(status: status)
                .padding(1)
                .background(Color(uiColor: .systemBackground), in: Circle())
                .offset(x: 2, y: 2)
        }
    }

    private var placeholder: some View {
        Circle()
            .fill(.gray.opacity(0.25))
            .frame(width: size, height: size)
            .overlay {
                Text(String(friend.contactUsername.prefix(1)).uppercased())
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
    }
}

private struct FriendStatusDot: View {
    let status: String?

    var body: some View {
        Circle()
            .fill(color(for: status))
            .frame(width: 10, height: 10)
    }

    private func color(for status: String?) -> Color {
        switch status?.lowercased() {
        case "sociable": return .blue
        case "online": return .green
        case "away": return .yellow
        case "busy": return .red
        case "offline", "invisible": return .gray
        default: return .gray
        }
    }
}
