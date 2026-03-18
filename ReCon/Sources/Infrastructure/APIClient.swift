import Foundation

final class APIClient {
    private let environment: AppEnvironment
    private let session: URLSession
    private let requestTimeout: TimeInterval
    private let maxResponseBytes: Int

    init(
        environment: AppEnvironment,
        session: URLSession? = nil,
        requestTimeout: TimeInterval = 30,
        maxResponseBytes: Int = 8 * 1024 * 1024
    ) {
        self.environment = environment
        self.session = session ?? APIClient.makeDefaultSession(timeout: requestTimeout)
        self.requestTimeout = requestTimeout
        self.maxResponseBytes = maxResponseBytes
    }

    func request(
        _ path: String,
        method: String,
        auth: AuthenticationData? = nil,
        extraHeaders: [String: String] = [:],
        body: Data? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: path, relativeTo: environment.apiBaseURL) else {
            throw AppError.transport("Invalid URL: \(path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let auth, auth.isAuthenticated {
            request.setValue(auth.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        }
        for (k, v) in extraHeaders {
            request.setValue(v, forHTTPHeaderField: k)
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AppError.invalidResponse
            }
            try validateResponseSize(data: data, response: http)
            try mapHTTPError(data: data, response: http)
            return (data, http)
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.transport(error.localizedDescription)
        }
    }

    private func mapHTTPError(data: Data, response: HTTPURLResponse) throws {
        guard response.statusCode >= 300 else { return }

        if response.statusCode == 403, let body = String(data: data, encoding: .utf8), body == "TOTP" {
            throw AppError.totpRequired
        }

        switch response.statusCode {
        case 400: throw AppError.invalidCredentials
        case 403: throw AppError.unauthorized
        case 404: throw AppError.notFound
        case 429: throw AppError.rateLimited
        case 500: throw AppError.serverError
        default:
            throw AppError.unknown("HTTP \(response.statusCode)")
        }
    }

    private static func makeDefaultSession(timeout: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    private func validateResponseSize(data: Data, response: HTTPURLResponse) throws {
        if data.count > maxResponseBytes {
            throw AppError.transport("Response payload too large.")
        }
        let expectedLength = response.expectedContentLength
        if expectedLength > Int64(maxResponseBytes) {
            throw AppError.transport("Response payload too large.")
        }
    }
}
