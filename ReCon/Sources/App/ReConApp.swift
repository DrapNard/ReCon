import SwiftUI
import UIKit

@main
struct ReConApp: App {
    @StateObject private var container = AppContainer()

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        appearance.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            RootView(app: container)
                .preferredColorScheme(container.settingsStore.settings.themeMode.colorScheme)
                .tint(Color(red: 0.21, green: 0.79, blue: 0.92))
        }
    }
}

private extension ThemePreference {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
