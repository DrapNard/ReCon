import SwiftUI

struct SessionsView: View {
    @ObservedObject var app: AppContainer
    @State private var sessions: [Session] = []
    @State private var loading = false
    @State private var errorText: String?

    var body: some View {
        List {
            if let errorText {
                Text(errorText).foregroundStyle(.red)
            }
            ForEach(sessions) { session in
                NavigationLink {
                    SessionDetailView(app: app, sessionID: session.id)
                } label: {
                    HStack(spacing: 12) {
                        SharedThumbnailView(urlString: session.thumbnailUrl, environment: app.environment, size: 44, fallbackSystemName: "person.3")
                        VStack(alignment: .leading) {
                            Text(RichTextFormatter.toAttributedString(session.name))
                                .lineLimit(2)
                            Text("\(session.joinedUsers)/\(session.maxUsers) Online")
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
            }
        }
        .navigationTitle("Sessions")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard app.auth.isAuthenticated else { return }
        loading = true
        defer { loading = false }

        do {
            sessions = try await app.repository.fetchSessions(auth: app.auth)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}

struct SessionDetailView: View {
    @ObservedObject var app: AppContainer
    let sessionID: String

    @State private var session: Session?
    @State private var errorText: String?

    var body: some View {
        Group {
            if let session {
                List {
                    Text(session.name)
                    Text("Host: \(session.hostUsername)")
                    Text("Users: \(session.joinedUsers)/\(session.maxUsers)")
                }
            } else if let errorText {
                Text(errorText).foregroundStyle(.red)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Session")
        .task { await load() }
    }

    private func load() async {
        do {
            session = try await app.repository.fetchSession(auth: app.auth, id: sessionID)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}
