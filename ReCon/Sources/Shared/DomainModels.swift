import Foundation

struct Friend: Identifiable, Codable, Equatable, Sendable {
    var id: String { contactUserId }
    let contactUserId: String
    let contactUsername: String
    let latestMessageTime: Date
    let contactStatus: String?
    let isAccepted: Bool?
    let onlineStatus: String?
    let profileIconUrl: String?

    private enum CodingKeys: String, CodingKey {
        case contactUserId = "id"
        case contactUsername
        case latestMessageTime
        case contactStatus
        case isAccepted
        case onlineStatus
        case profileIconUrl
    }

    init(
        contactUserId: String,
        contactUsername: String,
        latestMessageTime: Date,
        contactStatus: String?,
        isAccepted: Bool?,
        onlineStatus: String?,
        profileIconUrl: String?
    ) {
        self.contactUserId = contactUserId
        self.contactUsername = contactUsername
        self.latestMessageTime = latestMessageTime
        self.contactStatus = contactStatus
        self.isAccepted = isAccepted
        self.onlineStatus = onlineStatus
        self.profileIconUrl = profileIconUrl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contactUserId = try container.decode(String.self, forKey: .contactUserId)
        contactUsername = try container.decode(String.self, forKey: .contactUsername)
        latestMessageTime = try container.decodeIfPresent(Date.self, forKey: .latestMessageTime) ?? .distantPast
        contactStatus = try container.decodeIfPresent(String.self, forKey: .contactStatus)
        isAccepted = try container.decodeIfPresent(Bool.self, forKey: .isAccepted)
        onlineStatus = try container.decodeIfPresent(String.self, forKey: .onlineStatus)
        profileIconUrl = try container.decodeIfPresent(String.self, forKey: .profileIconUrl)
    }
}

struct RemoteUserProfile: Equatable, Sendable {
    let iconUrl: String
    let tagline: String?
    let description: String?
}

struct RemoteUser: Identifiable, Equatable, Sendable {
    let id: String
    let username: String
    let registrationDate: Date?
    let profile: RemoteUserProfile?
}

struct Session: Identifiable, Decodable, Equatable, Sendable {
    let id: String
    let name: String
    let hostUsername: String
    let maxUsers: Int
    let joinedUsers: Int
    let thumbnailUrl: String
    let sessionUsers: [SessionUser]
    let sessionURLs: [String]

    private enum CodingKeys: String, CodingKey {
        case id = "sessionId"
        case idAlt = "id"
        case name
        case hostUsername
        case maxUsers
        case maxUsersAlt = "totalActiveUsers"
        case joinedUsers
        case joinedUsersAlt = "totalJoinedUsers"
        case thumbnailUrl
        case sessionUsers
        case sessionURLs
    }

    init(id: String, name: String, hostUsername: String, maxUsers: Int, joinedUsers: Int, thumbnailUrl: String, sessionUsers: [SessionUser], sessionURLs: [String]) {
        self.id = id
        self.name = name
        self.hostUsername = hostUsername
        self.maxUsers = maxUsers
        self.joinedUsers = joinedUsers
        self.thumbnailUrl = thumbnailUrl
        self.sessionUsers = sessionUsers
        self.sessionURLs = sessionURLs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
            ?? c.decodeIfPresent(String.self, forKey: .idAlt)
            ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Unknown Session"
        hostUsername = try c.decodeIfPresent(String.self, forKey: .hostUsername) ?? "Unknown"
        maxUsers = try c.decodeIfPresent(Int.self, forKey: .maxUsers)
            ?? c.decodeIfPresent(Int.self, forKey: .maxUsersAlt)
            ?? 0
        joinedUsers = try c.decodeIfPresent(Int.self, forKey: .joinedUsers)
            ?? c.decodeIfPresent(Int.self, forKey: .joinedUsersAlt)
            ?? 0
        thumbnailUrl = try c.decodeIfPresent(String.self, forKey: .thumbnailUrl) ?? ""
        sessionUsers = try c.decodeIfPresent([SessionUser].self, forKey: .sessionUsers) ?? []
        sessionURLs = try c.decodeIfPresent([String].self, forKey: .sessionURLs) ?? []
    }

    init(map: [String: Any]) {
        id = (map["sessionId"] as? String) ?? (map["id"] as? String) ?? UUID().uuidString
        name = (map["name"] as? String) ?? "Unknown Session"
        hostUsername = (map["hostUsername"] as? String) ?? "Unknown"
        maxUsers = (map["maxUsers"] as? Int) ?? (map["totalActiveUsers"] as? Int) ?? 0
        joinedUsers = (map["joinedUsers"] as? Int) ?? (map["totalJoinedUsers"] as? Int) ?? 0
        thumbnailUrl = (map["thumbnailUrl"] as? String) ?? ""
        sessionUsers = (map["sessionUsers"] as? [[String: Any]] ?? []).map { item in
            SessionUser(
                id: (item["userID"] as? String) ?? (item["id"] as? String) ?? UUID().uuidString,
                username: (item["username"] as? String) ?? "Unknown",
                isPresent: (item["isPresent"] as? Bool) ?? true
            )
        }
        sessionURLs = (map["sessionURLs"] as? [String]) ?? []
    }
}

struct SessionUser: Decodable, Equatable, Sendable {
    let id: String
    let username: String
    let isPresent: Bool

    private enum CodingKeys: String, CodingKey {
        case id = "userID"
        case idAlt = "id"
        case username
        case isPresent
    }

    init(id: String, username: String, isPresent: Bool) {
        self.id = id
        self.username = username
        self.isPresent = isPresent
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
            ?? c.decodeIfPresent(String.self, forKey: .idAlt)
            ?? UUID().uuidString
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? "Unknown"
        isPresent = try c.decodeIfPresent(Bool.self, forKey: .isPresent) ?? true
    }
}

struct WorldRecord: Identifiable, Decodable, Equatable, Sendable {
    let id: String
    let ownerId: String
    let name: String
    let thumbnailUri: String
    let description: String

    private enum CodingKeys: String, CodingKey {
        case id
        case ownerId
        case name
        case thumbnailUri
        case description
    }

    init(id: String, ownerId: String, name: String, thumbnailUri: String, description: String) {
        self.id = id
        self.ownerId = ownerId
        self.name = name
        self.thumbnailUri = thumbnailUri
        self.description = description
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        ownerId = try c.decodeIfPresent(String.self, forKey: .ownerId) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Unnamed World"
        thumbnailUri = try c.decodeIfPresent(String.self, forKey: .thumbnailUri) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
    }
}

struct InventoryRecord: Identifiable, Decodable, Equatable, Sendable {
    let id: String
    let name: String
    let path: String
    let recordType: String
    let assetUri: String
    let thumbnailUri: String

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case recordType
        case assetUri
        case thumbnailUri
    }

    init(id: String, name: String, path: String, recordType: String, assetUri: String, thumbnailUri: String) {
        self.id = id
        self.name = name
        self.path = path
        self.recordType = recordType
        self.assetUri = assetUri
        self.thumbnailUri = thumbnailUri
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Unnamed"
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
        recordType = try c.decodeIfPresent(String.self, forKey: .recordType) ?? "unknown"
        assetUri = try c.decodeIfPresent(String.self, forKey: .assetUri) ?? ""
        thumbnailUri = try c.decodeIfPresent(String.self, forKey: .thumbnailUri) ?? ""
    }
}

struct Message: Identifiable, Codable, Equatable, Sendable {
    enum MessageType: String, Codable, Sendable {
        case text = "Text"
        case sound = "Sound"
        case sessionInvite = "SessionInvite"
        case object = "Object"
        case inviteRequest = "InviteRequest"
        case unknown
    }

    enum MessageState: String, Codable, Sendable {
        case local
        case sent
        case read
    }

    let id: String
    let recipientId: String
    let senderId: String
    let type: MessageType
    let content: String
    let sendTime: Date
    let lastUpdateTime: Date
    var state: MessageState

    private enum CodingKeys: String, CodingKey {
        case id
        case recipientId
        case senderId
        case content
        case sendTime
        case lastUpdateTime
        case state
        case type = "messageType"
    }
}

extension Message {
    init(map: [String: Any]) {
        let typeRaw = (map["messageType"] as? String) ?? "Text"
        let parsedType: MessageType = switch typeRaw.lowercased() {
        case "text": .text
        case "sound": .sound
        case "sessioninvite": .sessionInvite
        case "object": .object
        case "inviterequest": .inviteRequest
        default: .unknown
        }

        let send = Message.parseDate(map["sendTime"]) ?? .now
        let last = Message.parseDate(map["lastUpdateTime"]) ?? send
        let readTimeExists = map["readTime"] != nil
        self.init(
            id: (map["id"] as? String) ?? "MSG-\(UUID().uuidString)",
            recipientId: (map["recipientId"] as? String) ?? "",
            senderId: (map["senderId"] as? String) ?? "",
            type: parsedType,
            content: (map["content"] as? String) ?? "",
            sendTime: send,
            lastUpdateTime: last,
            state: readTimeExists ? .read : .sent
        )
    }

    private static func parseDate(_ value: Any?) -> Date? {
        guard let value else { return nil }
        if let text = value as? String {
            return Message.iso8601Fractional.date(from: text) ?? Message.iso8601.date(from: text)
        }
        return nil
    }

    private static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
