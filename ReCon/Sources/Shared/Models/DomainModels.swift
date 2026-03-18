import Foundation

struct Friend: Identifiable, Codable, Equatable, Sendable {
    var id: String { contactUserId }
    let contactUserId: String
    let contactUsername: String
    let latestMessageTime: Date
}

struct Session: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let name: String
    let hostUsername: String
    let maxUsers: Int
    let joinedUsers: Int
    let thumbnailUrl: String

    private enum CodingKeys: String, CodingKey {
        case id = "sessionId"
        case name
        case hostUsername
        case maxUsers
        case joinedUsers
        case thumbnailUrl
    }
}

struct WorldRecord: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let ownerId: String
    let name: String
    let thumbnailUri: String
    let description: String
}

struct InventoryRecord: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let name: String
    let path: String
    let recordType: String
    let assetUri: String
    let thumbnailUri: String
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
