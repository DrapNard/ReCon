import Foundation
import CryptoKit

final class ReConRepository {
    private let api: APIClient
    private let decoder: JSONDecoder

    init(api: APIClient) {
        self.api = api
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = Self.iso8601withFractional.date(from: value) ?? Self.iso8601.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(value)")
        }
        self.decoder = decoder
    }

    func searchUsers(needle: String, auth: AuthenticationData) async throws -> [Friend] {
        let encoded = needle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? needle
        let (data, _) = try await api.request("/users?name=\(encoded)", method: "GET", auth: auth)
        let users = try decoder.decode([UserDTO].self, from: data)
        return users.map {
            Friend(
                contactUserId: $0.id,
                contactUsername: $0.username,
                latestMessageTime: .distantPast,
                contactStatus: nil,
                isAccepted: nil,
                onlineStatus: nil,
                profileIconUrl: nil
            )
        }
    }

    func fetchContacts(auth: AuthenticationData, lastStatusUpdate: Date? = nil) async throws -> [Friend] {
        let query: String
        if let lastStatusUpdate {
            let stamp = Self.iso8601withFractional.string(from: lastStatusUpdate)
            let encoded = stamp.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? stamp
            query = "?lastStatusUpdate=\(encoded)"
        } else {
            query = ""
        }
        let (data, _) = try await api.request("/users/\(auth.userId)/contacts\(query)", method: "GET", auth: auth)
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw AppError.invalidResponse
        }
        return raw.map { map in
            let id = (map["id"] as? String) ?? (map["contactUserId"] as? String) ?? (map["ownerId"] as? String) ?? UUID().uuidString
            let username = (map["contactUsername"] as? String) ?? (map["username"] as? String) ?? id
            let latestMessageTime = Self.parseDate(map["latestMessageTime"]) ?? .distantPast
            let profileMap = map["profile"] as? [String: Any]
            let statusMap = map["userStatus"] as? [String: Any]
            let directStatus = map["onlineStatus"]
            let iconDirect = map["profileIconUrl"] as? String
            return Friend(
                contactUserId: id,
                contactUsername: username,
                latestMessageTime: latestMessageTime,
                contactStatus: map["contactStatus"] as? String,
                isAccepted: map["isAccepted"] as? Bool,
                onlineStatus: Self.parseOnlineStatus(statusMap?["onlineStatus"]) ?? Self.parseOnlineStatus(directStatus),
                profileIconUrl: (profileMap?["iconUrl"] as? String) ?? iconDirect
            )
        }
    }

    func fetchUserStatus(auth: AuthenticationData, userId: String) async throws -> String? {
        let (data, _) = try await api.request("/users/\(userId)/status", method: "GET", auth: auth)
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return Self.parseOnlineStatus(raw["onlineStatus"])
    }

    func fetchUser(auth: AuthenticationData, userId: String) async throws -> RemoteUser {
        let (data, _) = try await api.request("/users/\(userId)/", method: "GET", auth: auth)
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppError.invalidResponse
        }

        let profileMap = raw["profile"] as? [String: Any]
        let profile: RemoteUserProfile?
        if let profileMap {
            profile = RemoteUserProfile(
                iconUrl: (profileMap["iconUrl"] as? String) ?? "",
                tagline: profileMap["tagline"] as? String,
                description: profileMap["description"] as? String
            )
        } else {
            profile = nil
        }

        return RemoteUser(
            id: (raw["id"] as? String) ?? userId,
            username: (raw["username"] as? String) ?? userId,
            registrationDate: Self.parseDate(raw["registrationDate"]),
            profile: profile
        )
    }

    func fetchSessions(auth: AuthenticationData, filter: SessionFilter = .default) async throws -> [Session] {
        let (data, _) = try await api.request("/sessions\(filter.query)", method: "GET", auth: auth)
        do {
            return try decoder.decode([Session].self, from: data)
        } catch {
            guard let raw = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw error }
            return raw.map(parseSession)
        }
    }

    func fetchSession(auth: AuthenticationData, id: String) async throws -> Session {
        let (data, _) = try await api.request("/sessions/\(id)", method: "GET", auth: auth)
        do {
            return try decoder.decode(Session.self, from: data)
        } catch {
            guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw error }
            return parseSession(raw)
        }
    }

    func fetchWorlds(auth: AuthenticationData, offset: Int, limit: Int) async throws -> [WorldRecord] {
        try await searchWorlds(auth: auth, query: "", offset: offset, limit: limit)
    }

    func searchWorlds(auth: AuthenticationData, query: String, offset: Int, limit: Int) async throws -> [WorldRecord] {
        let requiredTags = searchTags(from: query)
        let payload: [String: Any] = [
            "requiredTags": requiredTags,
            "sortDirection": "Descending",
            "sortBy": "LastUpdateDate",
            "count": limit,
            "offset": offset,
            "recordType": "world"
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await api.request("/records/pagedSearch", method: "POST", auth: auth, body: body)
        do {
            let wrapped = try decoder.decode(WorldSearchResponse.self, from: data)
            return wrapped.records.map { WorldRecord(id: $0.id, ownerId: $0.ownerId, name: $0.name, thumbnailUri: $0.thumbnailUri, description: $0.description) }
        } catch {
            guard
                let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let records = root["records"] as? [[String: Any]]
            else { throw error }
            return records.map(parseWorld)
        }
    }

    func searchSessions(auth: AuthenticationData, query: String) async throws -> [Session] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return try await fetchSessions(auth: auth)
        }

        async let byNameTask = fetchSessions(
            auth: auth,
            filter: SessionFilter(
                includeEmptyHeadless: true,
                includeEnded: false,
                name: trimmed,
                hostName: "",
                minActiveUsers: 0
            )
        )
        async let byHostTask = fetchSessions(
            auth: auth,
            filter: SessionFilter(
                includeEmptyHeadless: true,
                includeEnded: false,
                name: "",
                hostName: trimmed,
                minActiveUsers: 0
            )
        )

        let merged = (try await byNameTask) + (try await byHostTask)
        var seen = Set<String>()
        return merged.filter { seen.insert($0.id).inserted }
    }

    func fetchInventory(auth: AuthenticationData, path: String) async throws -> [InventoryRecord] {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        let (data, _) = try await api.request("/users/\(auth.userId)/records?path=\(encoded)", method: "GET", auth: auth)
        do {
            let dtos = try decoder.decode([InventoryDTO].self, from: data)
            return dtos.map { InventoryRecord(id: $0.id, name: $0.name, path: $0.path, recordType: $0.recordType, assetUri: $0.assetUri, thumbnailUri: $0.thumbnailUri) }
        } catch {
            if let records = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return records.map(parseInventory)
            }
            if
                let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let records = root["records"] as? [[String: Any]
            ] {
                return records.map(parseInventory)
            }
            throw error
        }
    }

    func fetchInventoryRecord(auth: AuthenticationData, ownerId: String, recordId: String) async throws -> InventoryRecord {
        let (data, _) = try await api.request("/users/\(ownerId)/records/\(recordId)", method: "GET", auth: auth)
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppError.invalidResponse
        }
        return parseInventory(raw)
    }

    func fetchStorageQuota(auth: AuthenticationData) async throws -> StorageQuota {
        let (data, _) = try await api.request("/users/\(auth.userId)/storage", method: "GET", auth: auth)
        return try decoder.decode(StorageQuota.self, from: data)
    }

    func createInventoryFolder(auth: AuthenticationData, parentPath: String, folderName: String) async throws {
        let cleaned = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw AppError.unknown("Folder name cannot be empty.") }
        let id = Self.generateRecordID()
        let record = makeInventoryRecord(
            auth: auth,
            id: id,
            path: parentPath,
            name: cleaned,
            recordType: "directory",
            assetUri: "",
            thumbnailUri: "",
            tags: [cleaned.lowercased(), "recon", "folder"]
        )
        try await upsertInventoryRecord(auth: auth, recordID: id, body: record)
    }

    func saveWorldToInventory(auth: AuthenticationData, world: WorldRecord, folderPath: String) async throws {
        let id = Self.generateRecordID()
        let cleanedName = sanitizeRecordName(world.name)
        let linkURI = "resrec:///\(world.ownerId)/\(world.id)"
        let record = makeInventoryRecord(
            auth: auth,
            id: id,
            path: folderPath,
            name: cleanedName,
            recordType: "link",
            assetUri: linkURI,
            thumbnailUri: world.thumbnailUri,
            tags: ["world", "favorite", "recon", world.id.lowercased()]
        )
        try await upsertInventoryRecord(auth: auth, recordID: id, body: record)
    }

    func moveInventoryRecord(auth: AuthenticationData, record: InventoryRecord, destinationPath: String) async throws {
        let sourceOwner = auth.userId
        let (rawData, _) = try await api.request("/users/\(sourceOwner)/records/\(record.id)", method: "GET", auth: auth)
        guard var raw = try JSONSerialization.jsonObject(with: rawData) as? [String: Any] else {
            throw AppError.invalidResponse
        }
        raw["path"] = destinationPath
        raw["lastModificationTime"] = Self.iso8601withFractional.string(from: Date())
        if let localVersion = raw["localVersion"] as? Int {
            raw["localVersion"] = localVersion + 1
        } else {
            raw["localVersion"] = 1
        }
        let body = try JSONSerialization.data(withJSONObject: raw)
        _ = try await api.request("/users/\(sourceOwner)/records/\(record.id)", method: "PUT", auth: auth, body: body)
    }

    func deleteInventoryRecord(auth: AuthenticationData, recordId: String) async throws {
        _ = try await api.request("/users/\(auth.userId)/records/\(recordId)", method: "DELETE", auth: auth)
    }

    func createFolderLink(auth: AuthenticationData, sourceFolder: InventoryRecord, destinationPath: String, linkName: String?) async throws {
        let sourceOwner = auth.userId
        let linkRecordID = Self.generateRecordID()
        let cleanedName = (linkName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? (linkName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            : "\(sourceFolder.name) Link"
        let assetURI = "resrec:///\(sourceOwner)/\(sourceFolder.id)"
        let record = makeInventoryRecord(
            auth: auth,
            id: linkRecordID,
            path: destinationPath,
            name: cleanedName,
            recordType: "link",
            assetUri: assetURI,
            thumbnailUri: sourceFolder.thumbnailUri,
            tags: ["folder", "link", "recon", sourceFolder.id.lowercased()]
        )
        try await upsertInventoryRecord(auth: auth, recordID: linkRecordID, body: record)
    }

    func fetchMessages(auth: AuthenticationData, with userId: String, maxItems: Int = 50) async throws -> [Message] {
        let encoded = userId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userId
        let path = "/users/\(auth.userId)/messages?maxItems=\(maxItems)&user=\(encoded)&unread=false"
        let (data, _) = try await api.request(path, method: "GET", auth: auth)
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw AppError.invalidResponse
        }
        return raw.map(Message.init(map:))
            .sorted { $0.sendTime < $1.sendTime }
    }

    func uploadVoiceClipMessageRecord(
        auth: AuthenticationData,
        fileURL: URL,
        messageID: String
    ) async throws -> [String: Any] {
        let data = try Data(contentsOf: fileURL)
        let hash = Self.sha256Hex(data: data)
        let fileExtension = {
            let ext = fileURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ext.isEmpty ? "ogg" : ext
        }()
        let baseName = {
            let value = fileURL.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? "voice" : value
        }()
        let assetUri = "resdb:///\(hash).\(fileExtension)"

        let now = Date()
        let recordID = Self.generateRecordID()
        let record: [String: Any] = [
            "id": recordID,
            "ownerId": auth.userId,
            "assetUri": assetUri,
            "globalVersion": 0,
            "localVersion": 1,
            "name": baseName,
            "description": NSNull(),
            "tags": [baseName, "message_item", "message_id:\(messageID)", "recon", "voice", "message"],
            "recordType": "audio",
            "thumbnailUri": NSNull(),
            "isPublic": false,
            "isForPatreons": false,
            "isListed": false,
            "lastModificationTime": Self.iso8601withFractional.string(from: now),
            "resoniteDBManifest": [["hash": hash, "bytes": data.count]],
            "lastModifyingUserId": auth.userId,
            "lastModifyingMachineId": auth.secretMachineIdHash,
            "creationTime": Self.iso8601withFractional.string(from: now),
            "combinedRecordId": ["id": recordID, "ownerId": auth.userId, "isValid": true],
            "isSynced": false,
            "fetchedOn": Self.iso8601withFractional.string(from: now.addingTimeInterval(1)),
            "path": NSNull(),
            "manifest": [assetUri],
            "url": "resrec:///\(auth.userId)/\(recordID)",
            "isValidOwnerId": true,
            "isValidRecordId": true,
            "visits": 0,
            "rating": 0,
            "randomOrder": 0
        ]

        let preprocess = try await preprocessRecord(auth: auth, recordID: recordID, recordBody: record)
        let uploadNeeded = preprocess.resultDiffs.contains { diff in
            let dHash = (diff["hash"] as? String)?.lowercased() ?? ""
            let isUploaded = (diff["isUploaded"] as? Bool) ?? false
            return dHash == hash && !isUploaded
        }
        if uploadNeeded {
            let uploadMeta = try await beginAssetUpload(auth: auth, hash: hash)
            if uploadMeta.totalChunks > 0, uploadMeta.chunkSize > 0 {
                for chunkIndex in 0..<uploadMeta.totalChunks {
                    let start = chunkIndex * uploadMeta.chunkSize
                    let end = min(start + uploadMeta.chunkSize, data.count)
                    if start >= end { break }
                    let chunk = data.subdata(in: start..<end)
                    try await uploadAssetChunk(auth: auth, hash: hash, chunkIndex: chunkIndex, chunkData: chunk, filename: "\(baseName).\(fileExtension)")
                }
                try await finishAssetUpload(auth: auth, hash: hash)
            }
        }

        let body = try JSONSerialization.data(withJSONObject: record)
        _ = try await api.request("/users/\(auth.userId)/records/\(recordID)", method: "PUT", auth: auth, body: body)
        return record
    }
}

private extension ReConRepository {
    struct AssetUploadMeta {
        let chunkSize: Int
        let totalChunks: Int
    }

    struct PreprocessStatusPayload {
        let state: String
        let failReason: String
        let resultDiffs: [[String: Any]]
    }

    static let iso8601withFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parseDate(_ value: Any?) -> Date? {
        guard let value else { return nil }
        if let string = value as? String {
            return iso8601withFractional.date(from: string)
                ?? iso8601.date(from: string)
        }
        if let seconds = value as? Double {
            return Date(timeIntervalSince1970: seconds)
        }
        if let seconds = value as? Int {
            return Date(timeIntervalSince1970: Double(seconds))
        }
        return nil
    }

    static func parseOnlineStatus(_ value: Any?) -> String? {
        if let text = value as? String {
            if let idx = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return parseOnlineStatus(idx)
            }
            return text.lowercased()
        }
        if let idx = value as? Int { return parseOnlineStatus(idx) }
        return nil
    }

    static func parseOnlineStatus(_ idx: Int) -> String? {
        switch idx {
        case 0: return "offline"
        case 1: return "invisible"
        case 2: return "away"
        case 3: return "busy"
        case 4: return "online"
        case 5: return "sociable"
        default: return nil
        }
    }

    func parseSession(_ map: [String: Any]) -> Session {
        let users = (map["sessionUsers"] as? [[String: Any]] ?? []).map { item in
            SessionUser(
                id: (item["userID"] as? String) ?? (item["id"] as? String) ?? UUID().uuidString,
                username: (item["username"] as? String) ?? "Unknown",
                isPresent: (item["isPresent"] as? Bool) ?? true
            )
        }
        return Session(
            id: (map["sessionId"] as? String) ?? (map["id"] as? String) ?? UUID().uuidString,
            name: (map["name"] as? String) ?? "Unknown Session",
            hostUsername: (map["hostUsername"] as? String) ?? "Unknown",
            maxUsers: (map["maxUsers"] as? Int) ?? (map["totalActiveUsers"] as? Int) ?? 0,
            joinedUsers: (map["joinedUsers"] as? Int) ?? (map["totalJoinedUsers"] as? Int) ?? 0,
            thumbnailUrl: (map["thumbnailUrl"] as? String) ?? "",
            sessionUsers: users,
            sessionURLs: (map["sessionURLs"] as? [String]) ?? []
        )
    }

    func parseWorld(_ map: [String: Any]) -> WorldRecord {
        WorldRecord(
            id: (map["id"] as? String) ?? UUID().uuidString,
            ownerId: (map["ownerId"] as? String) ?? "",
            name: (map["name"] as? String) ?? "Unnamed World",
            thumbnailUri: (map["thumbnailUri"] as? String) ?? "",
            description: (map["description"] as? String) ?? ""
        )
    }

    func parseInventory(_ map: [String: Any]) -> InventoryRecord {
        InventoryRecord(
            id: (map["id"] as? String) ?? UUID().uuidString,
            name: (map["name"] as? String) ?? "Unnamed",
            path: (map["path"] as? String) ?? "",
            recordType: (map["recordType"] as? String) ?? "unknown",
            assetUri: (map["assetUri"] as? String) ?? "",
            thumbnailUri: (map["thumbnailUri"] as? String) ?? ""
        )
    }

    private func upsertInventoryRecord(auth: AuthenticationData, recordID: String, body: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: body)
        _ = try await api.request("/users/\(auth.userId)/records/\(recordID)", method: "PUT", auth: auth, body: data)
    }

    private func makeInventoryRecord(
        auth: AuthenticationData,
        id: String,
        path: String,
        name: String,
        recordType: String,
        assetUri: String,
        thumbnailUri: String,
        tags: [String]
    ) -> [String: Any] {
        let now = Self.iso8601withFractional.string(from: Date())
        return [
            "id": id,
            "ownerId": auth.userId,
            "assetUri": assetUri,
            "globalVersion": 0,
            "localVersion": 1,
            "name": name,
            "description": NSNull(),
            "tags": tags,
            "recordType": recordType,
            "thumbnailUri": thumbnailUri.isEmpty ? NSNull() : thumbnailUri,
            "isPublic": false,
            "isForPatreons": false,
            "isListed": false,
            "lastModificationTime": now,
            "resoniteDBManifest": [],
            "lastModifyingUserId": auth.userId,
            "lastModifyingMachineId": auth.secretMachineIdHash,
            "creationTime": now,
            "combinedRecordId": [
                "id": id,
                "ownerId": auth.userId,
                "isValid": true
            ],
            "isSynced": false,
            "fetchedOn": now,
            "path": path,
            "manifest": [],
            "url": "resrec:///\(auth.userId)/\(id)",
            "isValidOwnerId": true,
            "isValidRecordId": true,
            "visits": 0,
            "rating": 0,
            "randomOrder": 0
        ]
    }

    private func sanitizeRecordName(_ raw: String) -> String {
        let stripped = raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let collapsed = stripped.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "World Favorite" : trimmed
    }

    private func searchTags(from query: String) -> [String] {
        query
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "[^\\p{L}\\p{N}_\\-\\s]", with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }
    }

    private static func generateRecordID() -> String {
        "R-\(UUID().uuidString.lowercased())"
    }

    static func sha256Hex(data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func beginAssetUpload(auth: AuthenticationData, hash: String) async throws -> AssetUploadMeta {
        let (data, _) = try await api.request("/users/\(auth.userId)/assets/\(hash)/chunks", method: "POST", auth: auth)
        guard let map = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppError.invalidResponse
        }
        let state = ((map["uploadState"] as? String) ?? (map["uploadStat"] as? String) ?? "").lowercased()
        if state == "failed" {
            throw AppError.unknown("Voice upload initialization failed.")
        }
        let chunkSize = (map["chunkSize"] as? Int) ?? 0
        let totalChunks = (map["totalChunks"] as? Int) ?? 0
        return AssetUploadMeta(chunkSize: chunkSize, totalChunks: totalChunks)
    }

    func preprocessRecord(auth: AuthenticationData, recordID: String, recordBody: [String: Any]) async throws -> PreprocessStatusPayload {
        let payload = try JSONSerialization.data(withJSONObject: recordBody)
        let (data, _) = try await api.request("/users/\(auth.userId)/records/\(recordID)/preprocess", method: "POST", auth: auth, body: payload)
        guard let map = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppError.invalidResponse
        }
        guard let preprocessID = map["id"] as? String, !preprocessID.isEmpty else {
            throw AppError.invalidResponse
        }
        return try await awaitPreprocess(auth: auth, recordID: recordID, preprocessID: preprocessID)
    }

    func awaitPreprocess(auth: AuthenticationData, recordID: String, preprocessID: String) async throws -> PreprocessStatusPayload {
        let maxAttempts = 35
        for _ in 0..<maxAttempts {
            let (data, _) = try await api.request(
                "/users/\(auth.userId)/records/\(recordID)/preprocess/\(preprocessID)",
                method: "GET",
                auth: auth
            )
            guard let map = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AppError.invalidResponse
            }
            let rawState = ((map["state"] as? String) ?? "").lowercased()
            if rawState == "preprocessing" || rawState.isEmpty {
                try await Task.sleep(nanoseconds: 350_000_000)
                continue
            }
            let failReason = (map["failReason"] as? String) ?? "Unknown preprocess failure"
            let resultDiffs = (map["resultDiffs"] as? [[String: Any]]) ?? []
            if rawState == "success" {
                return PreprocessStatusPayload(state: rawState, failReason: "", resultDiffs: resultDiffs)
            }
            throw AppError.unknown("Voice preprocess failed: \(failReason)")
        }
        throw AppError.unknown("Voice preprocess timed out.")
    }

    func finishAssetUpload(auth: AuthenticationData, hash: String) async throws {
        _ = try await api.request("/users/\(auth.userId)/assets/\(hash)/chunks", method: "PATCH", auth: auth)
    }

    func uploadAssetChunk(
        auth: AuthenticationData,
        hash: String,
        chunkIndex: Int,
        chunkData: Data,
        filename: String
    ) async throws {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: multipart/form-data\r\n\r\n".data(using: .utf8)!)
        body.append(chunkData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        _ = try await api.request(
            "/users/\(auth.userId)/assets/\(hash)/chunks/\(chunkIndex)",
            method: "POST",
            auth: auth,
            extraHeaders: ["Content-Type": "multipart/form-data; boundary=\(boundary)"],
            body: body
        )
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
        if !name.isEmpty { items.append("name=\(urlEncoded(name))") }
        if !hostName.isEmpty { items.append(hostName.hasPrefix("U-") ? "hostId=\(urlEncoded(hostName))" : "hostName=\(urlEncoded(hostName))") }
        if minActiveUsers > 0 { items.append("minActiveUsers=\(minActiveUsers)") }
        return items.isEmpty ? "" : "?" + items.joined(separator: "&")
    }

    private func urlEncoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
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
