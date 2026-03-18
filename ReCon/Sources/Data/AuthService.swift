import Foundation

final class AuthService {
    private let api: APIClient
    private let keychain: KeychainStore

    init(api: APIClient, keychain: KeychainStore) {
        self.api = api
        self.keychain = keychain
    }

    func tryLogin(username: String, password: String, oneTimePad: String? = nil) async throws -> AuthenticationData {
        let machineId = UUID().uuidString
        let uid = UUID().uuidString.replacingOccurrences(of: "-", with: "")

        let body = LoginRequestBody(
            email: username.contains("@") ? username.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            username: username.contains("@") ? nil : username.trimmingCharacters(in: .whitespacesAndNewlines),
            authentication: .init(password: password),
            rememberMe: true,
            secretMachineId: machineId
        )
        let encoded = try JSONEncoder().encode(body)

        let headers: [String: String] = [
            "UID": uid,
            oneTimePad == nil ? "": "TOTP": oneTimePad ?? ""
        ].filter { !$0.key.isEmpty }

        let (data, _) = try await api.request("/userSessions", method: "POST", extraHeaders: headers, body: encoded)
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let entity = json["entity"] as? [String: Any],
            let userId = entity["userId"] as? String,
            let token = entity["token"] as? String,
            let secretMachineIdHash = entity["secretMachineIdHash"] as? String
        else {
            throw AppError.invalidResponse
        }

        let auth = AuthenticationData(userId: userId, token: token, secretMachineIdHash: secretMachineIdHash, uid: uid)
        persist(auth: auth, password: password)
        return auth
    }

    func tryCachedLogin() async -> AuthenticationData {
        guard
            let userId = keychain.get(.userId),
            let machineId = keychain.get(.machineId),
            let uid = keychain.get(.uid)
        else {
            return .unauthenticated
        }

        if let token = keychain.get(.token) {
            let auth = AuthenticationData(userId: userId, token: token, secretMachineIdHash: machineId, uid: uid)
            do {
                _ = try await api.request("/userSessions", method: "PATCH", auth: auth, extraHeaders: ["UID": uid])
                return auth
            } catch {
                // fallback below
            }
        }

        if let password = keychain.get(.password) {
            let rawUser = userId.hasPrefix("U-") ? String(userId.dropFirst(2)) : userId
            do {
                return try await tryLogin(username: rawUser, password: password)
            } catch {
                return .unauthenticated
            }
        }

        return .unauthenticated
    }

    func logout() {
        keychain.clearAll()
    }

    private func persist(auth: AuthenticationData, password: String) {
        keychain.set(auth.userId, for: .userId)
        keychain.set(auth.secretMachineIdHash, for: .machineId)
        keychain.set(auth.token, for: .token)
        keychain.set(auth.uid, for: .uid)
        keychain.set(password, for: .password)
    }
}
