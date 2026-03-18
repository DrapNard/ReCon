import Foundation

final class HubClient {
    private let environment: AppEnvironment
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var handlers: [String: ([Any]) -> Void] = [:]
    private var responseHandlers: [String: (Any) -> Void] = [:]
    private let eof = "\u{001e}"

    init(environment: AppEnvironment, session: URLSession = .shared) {
        self.environment = environment
        self.session = session
    }

    func setHandler(_ target: String, handler: @escaping ([Any]) -> Void) {
        handlers[target.lowercased()] = handler
    }

    func connect(headers: [String: String]) {
        guard var components = URLComponents(url: environment.hubURL, resolvingAgainstBaseURL: true) else { return }
        components.scheme = "wss"
        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        task = session.webSocketTask(with: request)
        task?.resume()
        task?.send(.string("{\"protocol\":\"json\", \"version\":1}\(eof)")) { _ in }
        listenLoop()
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        responseHandlers.removeAll()
    }

    func send(target: String, arguments: [Any] = [], onResponse: ((Any) -> Void)? = nil) {
        guard let task else { return }
        let invocationId = UUID().uuidString
        if let onResponse {
            responseHandlers[invocationId] = onResponse
        }

        let payload: [String: Any] = [
            "type": 1,
            "invocationId": invocationId,
            "target": target,
            "arguments": arguments
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }

        task.send(.string(text + eof)) { _ in }
    }

    private func listenLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                break
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleFrameText(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleFrameText(text)
                    }
                @unknown default:
                    break
                }
                self.listenLoop()
            }
        }
    }

    private func handleFrameText(_ text: String) {
        let frames = text.split(separator: Character(eof), omittingEmptySubsequences: true)
        for frame in frames {
            guard
                let data = frame.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let type = object["type"] as? Int
            else { continue }

            switch type {
            case 1, 4:
                let target = (object["target"] as? String ?? "").lowercased()
                let args = object["arguments"] as? [Any] ?? []
                handlers[target]?(args)
            case 2, 3:
                if let invocation = object["invocationId"] as? String {
                    responseHandlers[invocation]?(object["result"] ?? [:])
                    responseHandlers.removeValue(forKey: invocation)
                }
            default:
                break
            }
        }
    }
}
