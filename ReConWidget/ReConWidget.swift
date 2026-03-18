import WidgetKit
import SwiftUI

private enum WidgetConfig {
    static let appGroupID = "group.com.drapnard.recon"
    static let snapshotKey = "widget.snapshot.v1"
}

private struct WidgetSnapshot: Decodable {
    let profileStatus: String
    let onlineContacts: Int
    let openSessions: Int
    let storageUsedBytes: Int
    let storageQuotaBytes: Int
    let latestSessionName: String
    let latestSessionHost: String
    let latestSessionUsers: Int
    let latestSessionMaxUsers: Int
    let onlineFriendNames: [String]
    let lastUpdated: String

    static let empty = WidgetSnapshot(
        profileStatus: "offline",
        onlineContacts: 0,
        openSessions: 0,
        storageUsedBytes: 0,
        storageQuotaBytes: 0,
        latestSessionName: "",
        latestSessionHost: "",
        latestSessionUsers: 0,
        latestSessionMaxUsers: 0,
        onlineFriendNames: [],
        lastUpdated: ""
    )

    private enum CodingKeys: String, CodingKey {
        case profileStatus
        case onlineContacts
        case openSessions
        case storageUsedBytes
        case storageQuotaBytes
        case latestSessionName
        case latestSessionHost
        case latestSessionUsers
        case latestSessionMaxUsers
        case onlineFriendNames
        case lastUpdated
    }

    init(
        profileStatus: String,
        onlineContacts: Int,
        openSessions: Int,
        storageUsedBytes: Int,
        storageQuotaBytes: Int,
        latestSessionName: String,
        latestSessionHost: String,
        latestSessionUsers: Int,
        latestSessionMaxUsers: Int,
        onlineFriendNames: [String],
        lastUpdated: String
    ) {
        self.profileStatus = profileStatus
        self.onlineContacts = onlineContacts
        self.openSessions = openSessions
        self.storageUsedBytes = storageUsedBytes
        self.storageQuotaBytes = storageQuotaBytes
        self.latestSessionName = latestSessionName
        self.latestSessionHost = latestSessionHost
        self.latestSessionUsers = latestSessionUsers
        self.latestSessionMaxUsers = latestSessionMaxUsers
        self.onlineFriendNames = onlineFriendNames
        self.lastUpdated = lastUpdated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profileStatus = try container.decodeIfPresent(String.self, forKey: .profileStatus) ?? "offline"
        onlineContacts = try container.decodeIfPresent(Int.self, forKey: .onlineContacts) ?? 0
        openSessions = try container.decodeIfPresent(Int.self, forKey: .openSessions) ?? 0
        storageUsedBytes = try container.decodeIfPresent(Int.self, forKey: .storageUsedBytes) ?? 0
        storageQuotaBytes = try container.decodeIfPresent(Int.self, forKey: .storageQuotaBytes) ?? 0
        latestSessionName = try container.decodeIfPresent(String.self, forKey: .latestSessionName) ?? ""
        latestSessionHost = try container.decodeIfPresent(String.self, forKey: .latestSessionHost) ?? ""
        latestSessionUsers = try container.decodeIfPresent(Int.self, forKey: .latestSessionUsers) ?? 0
        latestSessionMaxUsers = try container.decodeIfPresent(Int.self, forKey: .latestSessionMaxUsers) ?? 0
        onlineFriendNames = try container.decodeIfPresent([String].self, forKey: .onlineFriendNames) ?? []
        lastUpdated = try container.decodeIfPresent(String.self, forKey: .lastUpdated) ?? ""
    }
}

private struct ReConWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

private struct ReConWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReConWidgetEntry {
        ReConWidgetEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (ReConWidgetEntry) -> Void) {
        completion(ReConWidgetEntry(date: Date(), snapshot: loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReConWidgetEntry>) -> Void) {
        let entry = ReConWidgetEntry(date: Date(), snapshot: loadSnapshot())
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadSnapshot() -> WidgetSnapshot {
        let defaults = UserDefaults(suiteName: WidgetConfig.appGroupID) ?? .standard
        guard let data = defaults.data(forKey: WidgetConfig.snapshotKey) else { return .empty }
        return (try? JSONDecoder().decode(WidgetSnapshot.self, from: data)) ?? .empty
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReConWidgetView: View {
    let entry: ReConWidgetProvider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ReCon Status")
                .font(.headline)

            HStack(spacing: 10) {
                MetricTile(title: "Contacts Online", value: "\(entry.snapshot.onlineContacts)", systemImage: "person.2.fill")
                MetricTile(title: "Open Sessions", value: "\(entry.snapshot.openSessions)", systemImage: "person.3.fill")
            }

            HStack(spacing: 10) {
                MetricTile(title: "Inventory", value: storageText(entry.snapshot), systemImage: "internaldrive")
                MetricTile(title: "Profile", value: entry.snapshot.profileStatus.capitalized, systemImage: "person.crop.circle")
            }
        }
        .padding()
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color.blue.opacity(0.35), Color.green.opacity(0.28), Color.indigo.opacity(0.38)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func storageText(_ snapshot: WidgetSnapshot) -> String {
        guard snapshot.storageQuotaBytes > 0 else { return "0%" }
        let ratio = Double(snapshot.storageUsedBytes) / Double(snapshot.storageQuotaBytes)
        return "\(Int((ratio * 100).rounded()))%"
    }
}

struct ReConWidget: Widget {
    let kind: String = "ReConWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ReConWidgetProvider()) { entry in
            ReConWidgetView(entry: entry)
        }
        .configurationDisplayName("ReCon Overview")
        .description("Online contacts, open sessions, inventory status, and profile status.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct LatestSessionWidgetView: View {
    let entry: ReConWidgetProvider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Latest Session", systemImage: "person.3.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            if entry.snapshot.latestSessionName.isEmpty {
                Text("No session available")
                    .font(.headline)
            } else {
                Text(entry.snapshot.latestSessionName)
                    .font(.headline)
                    .lineLimit(3)
                Text("Host: \(entry.snapshot.latestSessionHost)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(entry.snapshot.latestSessionUsers)/\(entry.snapshot.latestSessionMaxUsers) online")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color.teal.opacity(0.36), Color.blue.opacity(0.28), Color.indigo.opacity(0.36)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct ReConLatestSessionWidget: Widget {
    let kind: String = "ReConLatestSessionWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ReConWidgetProvider()) { entry in
            LatestSessionWidgetView(entry: entry)
        }
        .configurationDisplayName("ReCon Latest Session")
        .description("Shows the latest active session.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct OnlineFriendsWidgetView: View {
    let entry: ReConWidgetProvider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Online Friends", systemImage: "person.2.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(entry.snapshot.onlineContacts)")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            if entry.snapshot.onlineFriendNames.isEmpty {
                Text("No contacts online")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(entry.snapshot.onlineFriendNames.prefix(3).joined(separator: ", "))
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color.green.opacity(0.35), Color.cyan.opacity(0.25), Color.blue.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct ReConOnlineFriendsWidget: Widget {
    let kind: String = "ReConOnlineFriendsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ReConWidgetProvider()) { entry in
            OnlineFriendsWidgetView(entry: entry)
        }
        .configurationDisplayName("ReCon Online Friends")
        .description("Shows online friends and quick names.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemMedium) {
    ReConWidget()
} timeline: {
    ReConWidgetEntry(date: .now, snapshot: .empty)
}
