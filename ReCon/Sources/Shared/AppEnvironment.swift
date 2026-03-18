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

enum AssetURLResolver {
    static func resolveImageURL(_ raw: String?, environment: AppEnvironment) -> URL? {
        resolveAssetURL(raw, environment: environment, keepExtension: false)
    }

    static func resolveMediaURL(_ raw: String?, environment: AppEnvironment) -> URL? {
        resolveAssetURL(raw, environment: environment, keepExtension: true)
    }

    private static func resolveAssetURL(_ raw: String?, environment: AppEnvironment, keepExtension: Bool) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            guard
                let url = URL(string: raw),
                url.scheme?.lowercased() == "https",
                url.host?.isEmpty == false
            else {
                return nil
            }
            return url
        }
        if raw.hasPrefix("resdb:///") || raw.hasPrefix("resdb://") {
            let basename = raw
                .split(separator: "/")
                .last
                .map(String.init) ?? ""
            let safeBasename = basename.replacingOccurrences(of: #"[^A-Za-z0-9._-]"#, with: "", options: .regularExpression)
            let filename = keepExtension
                ? safeBasename
                : (safeBasename.split(separator: ".").first.map(String.init) ?? "")
            guard !filename.isEmpty else { return nil }
            return environment.assetsBaseURL.appendingPathComponent(filename)
        }
        return nil
    }
}
