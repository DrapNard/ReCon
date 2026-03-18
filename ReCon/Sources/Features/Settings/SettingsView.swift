import SwiftUI

struct SettingsView: View {
    @Environment private var app: AppContainer
    @State private var showProfile = false

    var body: some View {
        Form {
            Section("Notifications") {
                Button("Request Notification Permission") {
                    Task {
                        let granted = await app.notificationService.requestPermission()
                        var current = app.settingsStore.settings
                        current.notificationsDenied = !granted
                        app.settingsStore.save(current)
                    }
                }
            }

            Section("Appearance") {
                Picker("Theme Mode", selection: Binding(
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
            }

            Section("Account") {
                Button("My Profile") {
                    showProfile = true
                }
                Button("Sign out", role: .destructive) {
                    app.logout()
                }
            }

            Section("About") {
                Link("Open ReCon GitHub", destination: URL(string: "https://github.com/Nutcake/ReCon")!)
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showProfile) {
            NavigationStack {
                ProfileView()
            }
        }
    }
}
