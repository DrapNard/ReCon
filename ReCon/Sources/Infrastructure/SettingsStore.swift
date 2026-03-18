import Foundation
import Combine

@MainActor
final class SettingsStore: ObservableObject {
    private let key = "settings.native"
    private let defaults: UserDefaults

    @Published var settings: AppSettings

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if
            let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        {
            self.settings = decoded
        } else {
            self.settings = .default
        }
    }

    func save(_ newValue: AppSettings) {
        settings = newValue
        if let data = try? JSONEncoder().encode(newValue) {
            defaults.set(data, forKey: key)
        }
    }
}
