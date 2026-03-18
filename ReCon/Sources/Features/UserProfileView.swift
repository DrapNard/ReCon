import SwiftUI

struct SessionUserProfileView: View {
    @ObservedObject var app: AppContainer
    let userId: String
    let fallbackUsername: String
    let initialUser: RemoteUser?
    let initialContactStatus: String

    @State private var user: RemoteUser?
    @State private var onlineStatus: String = "offline"
    @State private var contactStatus: String = "none"
    @State private var actionLoading = false
    @State private var actionError: String?
    @State private var profileAccent: Color = .green

    var body: some View {
        ZStack {
            ReConBackdrop(style: .sessions)
                .overlay(
                    LinearGradient(
                        colors: [profileAccent.opacity(0.34), profileAccent.opacity(0.12), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    DynamicTintedRow(urlString: "", environment: app.environment, fallback: .green) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                ProfileAvatarView(
                                    username: currentUsername,
                                    iconUrl: user?.profile?.iconUrl,
                                    environment: app.environment,
                                    size: 64
                                )
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(currentUsername)
                                        .font(.title3.weight(.semibold))
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(statusColor(onlineStatus))
                                            .frame(width: 10, height: 10)
                                        Text(onlineStatus.capitalized)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }

                            Text("User ID: \(userId)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let registrationDate = user?.registrationDate {
                                Text("Registered: \(registrationDate.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    DynamicTintedRow(urlString: "", environment: app.environment, fallback: .green) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Social")
                                .font(.headline)
                            Text("Relationship: \(contactStatus.capitalized)")
                                .foregroundStyle(.secondary)

                            HStack(spacing: 10) {
                                Button(primaryActionTitle) {
                                    Task { await runPrimaryAction() }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(actionLoading)

                                Button(contactStatus == "blocked" ? "Unblock" : "Block") {
                                    Task { await updateContact(to: contactStatus == "blocked" ? "ignored" : "blocked") }
                                }
                                .buttonStyle(.bordered)
                                .disabled(actionLoading)
                            }

                            if let actionError {
                                Text(actionError)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    if let tagline = user?.profile?.tagline, !tagline.isEmpty {
                        DynamicTintedRow(urlString: "", environment: app.environment, fallback: .green) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Tagline")
                                    .font(.headline)
                                Text(tagline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let description = user?.profile?.description, !description.isEmpty {
                        DynamicTintedRow(urlString: "", environment: app.environment, fallback: .green) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("About")
                                    .font(.headline)
                                Text(description)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 18)
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var currentUsername: String {
        user?.username ?? initialUser?.username ?? fallbackUsername
    }

    private var primaryActionTitle: String {
        switch contactStatus {
        case "accepted", "requested":
            return "Remove Friend"
        case "blocked":
            return "Unblock"
        default:
            return "Add Friend"
        }
    }

    private func runPrimaryAction() async {
        switch contactStatus {
        case "accepted", "requested", "blocked":
            await updateContact(to: "ignored")
        default:
            await updateContact(to: "accepted")
        }
    }

    private func load() async {
        user = initialUser
        contactStatus = initialContactStatus.lowercased().isEmpty ? "none" : initialContactStatus.lowercased()
        if let icon = initialUser?.profile?.iconUrl, !icon.isEmpty {
            profileAccent = StableTintPalette.color(for: icon, fallback: .green)
        } else {
            profileAccent = StableTintPalette.color(for: userId, fallback: .green)
        }
        app.requestStatuses(for: [userId])

        do {
            let resolvedUser = try await app.repository.fetchUser(auth: app.auth, userId: userId)
            user = resolvedUser
            let key = resolvedUser.profile?.iconUrl ?? resolvedUser.id
            profileAccent = StableTintPalette.color(for: key, fallback: .green)
            if
                let icon = resolvedUser.profile?.iconUrl,
                let url = AssetURLResolver.resolveImageURL(icon, environment: app.environment),
                let dominant = await DominantColorPalette.color(for: url)
            {
                profileAccent = dominant
            }
        } catch {
            // Keep fallback user data when user endpoint is unavailable.
        }

        do {
            if let fetchedStatus = try await app.repository.fetchUserStatus(auth: app.auth, userId: userId) {
                onlineStatus = fetchedStatus
            } else {
                onlineStatus = app.effectiveStatus(for: userId, fallback: "offline")
            }
        } catch {
            onlineStatus = app.effectiveStatus(for: userId, fallback: "offline")
        }

        do {
            let contactList = try await app.repository.fetchContacts(auth: app.auth)
            if let contact = contactList.first(where: { $0.contactUserId == userId }) {
                let normalized = (contact.contactStatus ?? (contact.isAccepted == true ? "accepted" : "none")).lowercased()
                contactStatus = normalized.isEmpty ? "none" : normalized
            }
        } catch {
            // Keep current status if contacts endpoint fails.
        }
    }

    private func updateContact(to newStatus: String) async {
        actionLoading = true
        actionError = nil
        defer { actionLoading = false }

        let ok = await app.updateContact(
            userId: userId,
            username: currentUsername,
            profileIconUrl: user?.profile?.iconUrl,
            contactStatus: newStatus
        )
        if ok {
            contactStatus = newStatus
        } else {
            actionError = "Failed to update contact."
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
}

private struct ProfileAvatarView: View {
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
