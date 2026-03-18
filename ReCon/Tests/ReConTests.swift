import XCTest
@testable import ReConNative

final class ReConNativeTests: XCTestCase {
    func testRichTextFormatterRemovesTags() {
        let input = "<b>Hello</b><br>World"
        let value = String(RichTextFormatter.toAttributedString(input).characters)
        XCTAssertEqual(value, "Hello\nWorld")
    }

    func testAuthDataAuthenticatedFlag() {
        let auth = AuthenticationData(userId: "U-1", token: "token", secretMachineIdHash: "hash", uid: "uid")
        XCTAssertTrue(auth.isAuthenticated)
    }

    func testAssetURLResolverRejectsInsecureHTTPURL() {
        let url = AssetURLResolver.resolveImageURL("http://example.com/avatar.webp", environment: .default)
        XCTAssertNil(url)
    }

    func testAssetURLResolverAcceptsHTTPSURL() {
        let url = AssetURLResolver.resolveImageURL("https://example.com/avatar.webp", environment: .default)
        XCTAssertEqual(url?.absoluteString, "https://example.com/avatar.webp")
    }

    func testAssetURLResolverSanitizesResdbPath() {
        let url = AssetURLResolver.resolveMediaURL("resdb:///abc123!.webp", environment: .default)
        XCTAssertEqual(url?.absoluteString, "https://assets.resonite.com/abc123.webp")
    }

    func testAPIClientRejectsOversizedPayload() async {
        let session = makeMockSession(handler: { request in
            let data = Data(repeating: 1, count: 32)
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://api.resonite.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Length": "32"]
            )!
            return (data, response)
        })
        let client = APIClient(environment: .default, session: session, maxResponseBytes: 16)

        do {
            _ = try await client.request("/sessions", method: "GET")
            XCTFail("Expected oversized payload failure")
        } catch let error as AppError {
            XCTAssertEqual(error, .transport("Response payload too large."))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAPIClientMapsTransportErrors() async {
        let session = makeMockSession(handler: { _ in
            throw URLError(.timedOut)
        })
        let client = APIClient(environment: .default, session: session)

        do {
            _ = try await client.request("/sessions", method: "GET")
            XCTFail("Expected transport failure")
        } catch let error as AppError {
            guard case .transport(let message) = error else {
                XCTFail("Unexpected app error: \(error)")
                return
            }
            XCTAssertFalse(message.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeMockSession(
        handler: @escaping (URLRequest) throws -> (Data, HTTPURLResponse)
    ) -> URLSession {
        APIClientMockURLProtocol.requestHandler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [APIClientMockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

private final class APIClientMockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (Data, HTTPURLResponse))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
