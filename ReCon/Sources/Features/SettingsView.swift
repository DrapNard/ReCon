import SwiftUI

struct SettingsView: View {
    @ObservedObject var app: AppContainer
    @State private var showProfile = false
    @StateObject private var contributorsModel = ContributorsModel()
    private let statusOptions = ["online", "sociable", "away", "busy", "invisible", "offline"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                settingsSectionTitle("Appearance")
                VStack(spacing: 0) {
                    HStack {
                        Text("Theme Mode")
                        Spacer()
                        Picker("", selection: Binding(
                            get: { app.settingsStore.settings.themeMode },
                            set: {
                                var current = app.settingsStore.settings
                                current.themeMode = $0
                                app.settingsStore.save(current)
                            }
                        )) {
                            Text("System").tag(ThemePreference.system)
                            Text("Light").tag(ThemePreference.light)
                            Text("Dark").tag(ThemePreference.dark)
                        }
                        .labelsHidden()
                    }
                    .reconRowCard()
                }

                settingsSectionTitle("Notifications")
                Button("Request Notification Permission") {
                    Task {
                        let granted = await app.notificationService.requestPermission()
                        var current = app.settingsStore.settings
                        current.notificationsDenied = !granted
                        app.settingsStore.save(current)
                    }
                }
                .buttonStyle(.borderedProminent)

                settingsSectionTitle("Account")
                VStack(spacing: 12) {
                    HStack {
                        Text("Status")
                        Circle()
                            .fill(statusColor(app.selfOnlineStatus))
                            .frame(width: 10, height: 10)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { app.selfOnlineStatus },
                            set: { app.setSelfStatus($0) }
                        )) {
                            ForEach(statusOptions, id: \.self) { status in
                                Text(status.capitalized).tag(status)
                            }
                        }
                        .labelsHidden()
                    }
                    .reconRowCard()

                    Button("My Profile") {
                        showProfile = true
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.primary)
                    .reconRowCard()

                    Button("Sign out", role: .destructive) {
                        app.logout()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .buttonStyle(.borderless)
                    .reconRowCard()
                }

                settingsSectionTitle("About")
                VStack(spacing: 12) {
                    Link("Open Fork GitHub", destination: URL(string: "https://github.com/drapnard/ReCon")!)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .reconRowCard()
                    Link("Open Original GitHub", destination: URL(string: "https://github.com/Nutcake/ReCon")!)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .reconRowCard()
                }

                settingsSectionTitle("Contributors")
                VStack(alignment: .leading, spacing: 12) {
                    contributorPinnedCard(
                        title: "Fork Maintainer",
                        username: "drapnard",
                        profileURL: "https://github.com/drapnard",
                        accent: .cyan
                    )
                    contributorPinnedCard(
                        title: "Original Main Developer",
                        username: "Nutcake",
                        profileURL: "https://github.com/Nutcake",
                        accent: .orange
                    )
                }

                contributorsSectionTitle("Fork Contributors (drapnard/ReCon)")
                contributorsList(
                    contributorsModel.forkContributors,
                    loading: contributorsModel.isLoadingFork,
                    error: contributorsModel.forkError
                )

                contributorsSectionTitle("Original Contributors (Nutcake/ReCon)")
                contributorsList(
                    contributorsModel.originalContributors,
                    loading: contributorsModel.isLoadingOriginal,
                    error: contributorsModel.originalError
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .background(ReConBackdrop().ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await app.refreshSelfStatus() }
        .task { await contributorsModel.loadIfNeeded() }
        .sheet(isPresented: $showProfile) {
            NavigationStack {
                ProfileView(app: app)
            }
        }
    }

    private func settingsSectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.headline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
    }

    private func contributorsSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
    }

    private func contributorPinnedCard(title: String, username: String, profileURL: String, accent: Color) -> some View {
        Link(destination: URL(string: profileURL)!) {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: "https://github.com/\(username).png?size=96")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Circle().fill(Color.white.opacity(0.15))
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(username)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(accent.opacity(0.45), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func contributorsList(_ contributors: [GitHubContributor], loading: Bool, error: String?) -> some View {
        if loading && contributors.isEmpty {
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading contributors…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .reconRowCard()
        } else if let error {
            Text(error)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .reconRowCard()
        } else if contributors.isEmpty {
            Text("No contributors found.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .reconRowCard()
        } else {
            VStack(spacing: 10) {
                ForEach(contributors) { contributor in
                    Link(destination: URL(string: contributor.profileURL)!) {
                        HStack(spacing: 12) {
                            AsyncImage(url: URL(string: contributor.avatarURL)) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                default:
                                    Circle().fill(Color.white.opacity(0.15))
                                }
                            }
                            .frame(width: 36, height: 36)
                            .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(contributor.login)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("\(contributor.contributions) contributions")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "sociable": return .blue
        case "online": return .green
        case "away": return .yellow
        case "busy": return .red
        case "offline", "invisible": return .gray
        default: return .gray
        }
    }
}

private struct GitHubContributor: Decodable, Identifiable {
    let id: Int
    let login: String
    let avatarURL: String
    let profileURL: String
    let contributions: Int

    enum CodingKeys: String, CodingKey {
        case id
        case login
        case avatarURL = "avatar_url"
        case profileURL = "html_url"
        case contributions
    }
}

@MainActor
private final class ContributorsModel: ObservableObject {
    @Published var forkContributors: [GitHubContributor] = []
    @Published var originalContributors: [GitHubContributor] = []
    @Published var isLoadingFork = false
    @Published var isLoadingOriginal = false
    @Published var forkError: String?
    @Published var originalError: String?

    private var hasLoaded = false

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadForkContributors() }
            group.addTask { await self.loadOriginalContributors() }
        }
    }

    private func loadForkContributors() async {
        isLoadingFork = true
        defer { isLoadingFork = false }
        do {
            forkContributors = try await fetchContributors(owner: "drapnard", repo: "ReCon")
            forkError = nil
        } catch {
            forkError = "Failed to load fork contributors."
        }
    }

    private func loadOriginalContributors() async {
        isLoadingOriginal = true
        defer { isLoadingOriginal = false }
        do {
            originalContributors = try await fetchContributors(owner: "Nutcake", repo: "ReCon")
            originalError = nil
        } catch {
            originalError = "Failed to load original contributors."
        }
    }

    private func fetchContributors(owner: String, repo: String) async throws -> [GitHubContributor] {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/contributors?per_page=100") else {
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ReCon-iOS", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode([GitHubContributor].self, from: data)
        return decoded.sorted { $0.contributions > $1.contributions }
    }
}
