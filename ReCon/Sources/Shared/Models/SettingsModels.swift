import Foundation

enum ThemePreference: Int, CaseIterable, Codable, Sendable {
    case system = 0
    case light = 1
    case dark = 2
}

struct AppSettings: Codable, Equatable, Sendable {
    var notificationsDenied: Bool?
    var lastOnlineStatus: Int
    var lastDismissedVersion: String
    var machineId: String
    var themeMode: ThemePreference
    var sessionViewLastMinimumUsers: Int
    var sessionViewLastIncludeEnded: Bool
    var sessionViewLastIncludeEmpty: Bool
    var sessionViewLastIncludeIncompatible: Bool

    static let `default` = AppSettings(
        notificationsDenied: nil,
        lastOnlineStatus: 4,
        lastDismissedVersion: "0.0.0",
        machineId: UUID().uuidString,
        themeMode: .dark,
        sessionViewLastMinimumUsers: 0,
        sessionViewLastIncludeEnded: false,
        sessionViewLastIncludeEmpty: true,
        sessionViewLastIncludeIncompatible: false
    )
}
