import SwiftUI

struct FriendsView: View {
    @ObservedObject var app: AppContainer
    @State private var query = ""
    @State private var friends: [Friend] = []
    @State private var loading = false
    @State private var errorText: String?

    var body: some View {
        List(filteredFriends) { friend in
            NavigationLink {
                ChatView(app: app, friend: friend)
            } label: {
                HStack(spacing: 12) {
                    FriendAvatarView(friend: friend, size: 42, environment: app.environment)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(RichTextFormatter.toAttributedString(friend.contactUsername))
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            FriendStatusDot(status: friend.onlineStatus)
                            Text(friend.onlineStatus?.capitalized ?? "Unknown")
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
        .refreshable { await load() }
        .navigationTitle("ReCon")
        .navigationBarTitleDisplayMode(.inline)
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
        loading = true
        defer { loading = false }

        do {
            friends = try await app.repository.fetchContacts(auth: app.auth)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct FriendAvatarView: View {
    let friend: Friend
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

            FriendStatusDot(status: friend.onlineStatus)
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
