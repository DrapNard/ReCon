import SwiftUI

struct WorldsView: View {
    @ObservedObject var app: AppContainer
    @State private var worlds: [WorldRecord] = []
    @State private var loading = false
    @State private var errorText: String?

    var body: some View {
        List(worlds) { world in
            NavigationLink {
                WorldDetailView(world: world)
            } label: {
                HStack(spacing: 12) {
                    SharedThumbnailView(urlString: world.thumbnailUri, environment: app.environment, size: 44, fallbackSystemName: "globe")
                    VStack(alignment: .leading) {
                        Text(RichTextFormatter.toAttributedString(world.name))
                            .lineLimit(2)
                        if !world.description.isEmpty {
                            Text(RichTextFormatter.toAttributedString(world.description))
                                .lineLimit(2)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .overlay {
            if loading { ProgressView() }
            if worlds.isEmpty, !loading {
                ContentUnavailableView("No worlds found", systemImage: "globe")
            }
        }
        .navigationTitle("Worlds")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .safeAreaInset(edge: .bottom) {
            if let errorText {
                Text(errorText).foregroundStyle(.red).padding(8)
            }
        }
    }

    private func load() async {
        guard app.auth.isAuthenticated else { return }
        loading = true
        defer { loading = false }

        do {
            worlds = try await app.repository.fetchWorlds(auth: app.auth, offset: 0, limit: 16)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}

struct WorldDetailView: View {
    let world: WorldRecord

    var body: some View {
        List {
            Text(world.name).font(.headline)
            Text(world.description.isEmpty ? "No description" : world.description)
            Text("Owner: \(world.ownerId)")
            Text("ID: \(world.id)")
        }
        .navigationTitle("World")
    }
}
