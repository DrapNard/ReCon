import Foundation

final class ReConRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func searchUsers(needle: String, auth: AuthenticationData) async throws -> [Friend] {
        let encoded = needle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? needle
        let (data, _) = try await api.request("/users?name=\(encoded)", method: "GET", auth: auth)
        let users = try JSONDecoder().decode([UserDTO].self, from: data)
        return users.map { Friend(contactUserId: $0.id, contactUsername: $0.username, latestMessageTime: .distantPast) }
    }

    func fetchSessions(auth: AuthenticationData, filter: SessionFilter = .default) async throws -> [Session] {
        let (data, _) = try await api.request("/sessions\(filter.query)", method: "GET", auth: auth)
        return try JSONDecoder().decode([Session].self, from: data)
    }

    func fetchSession(auth: AuthenticationData, id: String) async throws -> Session {
        let (data, _) = try await api.request("/sessions/\(id)", method: "GET", auth: auth)
        return try JSONDecoder().decode(Session.self, from: data)
    }

    func fetchWorlds(auth: AuthenticationData, offset: Int, limit: Int) async throws -> [WorldRecord] {
        let payload: [String: Any] = [
            "requiredTags": [],
            "sortDirection": "Descending",
            "sortBy": "LastUpdateDate",
            "count": limit,
            "offset": offset,
            "recordType": "world"
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await api.request("/records/pagedSearch", method: "POST", auth: auth, body: body)
        let wrapped = try JSONDecoder().decode(WorldSearchResponse.self, from: data)
        return wrapped.records.map { WorldRecord(id: $0.id, ownerId: $0.ownerId, name: $0.name, thumbnailUri: $0.thumbnailUri, description: $0.description) }
    }

    func fetchInventory(auth: AuthenticationData, path: String) async throws -> [InventoryRecord] {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        let (data, _) = try await api.request("/users/\(auth.userId)/records?path=\(encoded)", method: "GET", auth: auth)
        let dtos = try JSONDecoder().decode([InventoryDTO].self, from: data)
        return dtos.map { InventoryRecord(id: $0.id, name: $0.name, path: $0.path, recordType: $0.recordType, assetUri: $0.assetUri, thumbnailUri: $0.thumbnailUri) }
    }

    func fetchStorageQuota(auth: AuthenticationData) async throws -> StorageQuota {
        let (data, _) = try await api.request("/users/\(auth.userId)/storage", method: "GET", auth: auth)
        return try JSONDecoder().decode(StorageQuota.self, from: data)
    }
}

struct SessionFilter: Sendable {
    var includeEmptyHeadless: Bool
    var includeEnded: Bool
    var name: String
    var hostName: String
    var minActiveUsers: Int

    static let `default` = SessionFilter(includeEmptyHeadless: true, includeEnded: false, name: "", hostName: "", minActiveUsers: 0)

    var query: String {
        var items = [
            "includeEmptyHeadless=\(includeEmptyHeadless)",
            "includeEnded=\(includeEnded)"
        ]
        if !name.isEmpty { items.append("name=\(name)") }
        if !hostName.isEmpty { items.append(hostName.hasPrefix("U-") ? "hostId=\(hostName)" : "hostName=\(hostName)") }
        if minActiveUsers > 0 { items.append("minActiveUsers=\(minActiveUsers)") }
        return items.isEmpty ? "" : "?" + items.joined(separator: "&")
    }
}

private struct UserDTO: Codable {
    let id: String
    let username: String
}

private struct WorldSearchResponse: Codable {
    let records: [WorldDTO]
}

private struct WorldDTO: Codable {
    let id: String
    let ownerId: String
    let name: String
    let thumbnailUri: String
    let description: String
}

private struct InventoryDTO: Codable {
    let id: String
    let name: String
    let path: String
    let recordType: String
    let assetUri: String
    let thumbnailUri: String
}

struct StorageQuota: Codable, Sendable {
    let id: String
    let usedBytes: Int
    let quotaBytes: Int
    let fullQuotaBytes: Int
}
