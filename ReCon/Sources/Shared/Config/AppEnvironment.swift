import Foundation

struct AppEnvironment: Sendable {
    let apiBaseURL: URL
    let assetsBaseURL: URL
    let hubURL: URL

    static let `default` = AppEnvironment(
        apiBaseURL: URL(string: "https://api.resonite.com")!,
        assetsBaseURL: URL(string: "https://assets.resonite.com")!,
        hubURL: URL(string: "https://api.resonite.com/hub")!
    )

    static func load(bundle: Bundle = .main) -> AppEnvironment {
        guard
            let url = bundle.url(forResource: "Environment", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            return .default
        }

        let api = URL(string: plist["API_BASE_URL"] as? String ?? "") ?? Self.default.apiBaseURL
        let assets = URL(string: plist["ASSETS_BASE_URL"] as? String ?? "") ?? Self.default.assetsBaseURL
        let hub = URL(string: plist["HUB_URL"] as? String ?? "") ?? Self.default.hubURL
        return AppEnvironment(apiBaseURL: api, assetsBaseURL: assets, hubURL: hub)
    }
}
