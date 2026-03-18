import SwiftUI

struct SettingsView: View {
    @ObservedObject var app: AppContainer
    @State private var showProfile = false
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
                Link("Open ReCon GitHub", destination: URL(string: "https://github.com/Nutcake/ReCon")!)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .reconRowCard()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .background(ReConBackdrop().ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await app.refreshSelfStatus() }
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
