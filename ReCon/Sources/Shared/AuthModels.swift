import Foundation

struct AuthenticationData: Codable, Equatable, Sendable {
    let userId: String
    let token: String
    let secretMachineIdHash: String
    let uid: String

    var isAuthenticated: Bool {
        !userId.isEmpty && !token.isEmpty && !secretMachineIdHash.isEmpty && !uid.isEmpty
    }

    static let unauthenticated = AuthenticationData(userId: "", token: "", secretMachineIdHash: "", uid: "")

    var authorizationHeaderValue: String {
        "res \(userId):\(token)"
    }
}

struct LoginRequestBody: Encodable {
    struct Authentication: Encodable {
        let type: String = "password"
        let password: String

        private enum CodingKeys: String, CodingKey {
            case type = "$type"
            case password
        }
    }

    let email: String?
    let username: String?
    let authentication: Authentication
    let rememberMe: Bool
    let secretMachineId: String
}
