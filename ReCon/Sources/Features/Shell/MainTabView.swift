import SwiftUI

struct MainTabView: View {
    @ObservedObject var app: AppContainer

    var body: some View {
        TabView {
            NavigationStack { FriendsView(app: app) }
                .tabItem { Label("Chat", systemImage: "message") }

            NavigationStack { SessionsView(app: app) }
                .tabItem { Label("Sessions", systemImage: "person.3") }

            NavigationStack { WorldsView(app: app) }
                .tabItem { Label("Worlds", systemImage: "globe") }

            NavigationStack { InventoryView(app: app) }
                .tabItem { Label("Inventory", systemImage: "shippingbox") }

            NavigationStack { SettingsView(app: app) }
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}

struct SharedThumbnailView: View {
    let urlString: String
    let environment: AppEnvironment
    let size: CGFloat
    let fallbackSystemName: String

    var body: some View {
        if let url = AssetURLResolver.resolveImageURL(urlString, environment: environment) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                placeholder
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.gray.opacity(0.2))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: fallbackSystemName)
                    .foregroundStyle(.secondary)
            }
    }
}
