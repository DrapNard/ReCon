import Foundation

enum AppError: LocalizedError, Equatable {
    case invalidCredentials
    case unauthorized
    case notFound
    case rateLimited
    case serverError
    case totpRequired
    case invalidResponse
    case transport(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid Credentials"
        case .unauthorized:
            return "You are not authorized to do that."
        case .notFound:
            return "Resource not found."
        case .rateLimited:
            return "You are being rate limited."
        case .serverError:
            return "Internal server error."
        case .totpRequired:
            return "TOTP_REQUIRED"
        case .invalidResponse:
            return "Server sent invalid response."
        case .transport(let message), .unknown(let message):
            return message
        }
    }
}
