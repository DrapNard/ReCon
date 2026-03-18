import Foundation

final class HubClient: @unchecked Sendable {
    private let environment: AppEnvironment
    private let session: URLSession
    private let stateLock = NSLock()
    private var task: URLSessionWebSocketTask?
    private var handlers: [String: [UUID: ([Any]) -> Void]] = [:]
    private var responseHandlers: [String: (Any) -> Void] = [:]
    private var pendingFrames: [String] = []
    private var connectionHeaders: [String: String] = [:]
    private var reconnectAttempt = 0
    private var isConnecting = false
    private var disconnectedManually = false
    private let eof = "\u{001e}"

    init(environment: AppEnvironment, session: URLSession = .shared) {
        self.environment = environment
        self.session = session
    }

    func setHandler(_ target: String, handler: @escaping ([Any]) -> Void) {
        withLock {
            handlers[target.lowercased()] = [UUID(): handler]
        }
    }

    @discardableResult
    func addHandler(_ target: String, handler: @escaping ([Any]) -> Void) -> UUID {
        withLock {
            let key = target.lowercased()
            let id = UUID()
            var bucket = handlers[key] ?? [:]
            bucket[id] = handler
            handlers[key] = bucket
            return id
        }
    }

    func removeHandler(_ target: String, id: UUID) {
        withLock {
            let key = target.lowercased()
            guard var bucket = handlers[key] else { return }
            bucket.removeValue(forKey: id)
            if bucket.isEmpty {
                handlers.removeValue(forKey: key)
            } else {
                handlers[key] = bucket
            }
        }
    }

    func connect(headers: [String: String]) {
        withLock {
            connectionHeaders = headers
            disconnectedManually = false
            isConnecting = true
        }
        guard var components = URLComponents(url: environment.hubURL, resolvingAgainstBaseURL: true) else {
            withLock { isConnecting = false }
            return
        }
        components.scheme = "wss"
        guard let url = components.url else {
            withLock { isConnecting = false }
            return
        }

        var request = URLRequest(url: url)
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let socketTask = session.webSocketTask(with: request)
        withLock {
            task = socketTask
        }
        socketTask.resume()
        socketTask.send(.string("{\"protocol\":\"json\", \"version\":1}\(eof)")) { [weak self] error in
            guard let self else { return }
            if error == nil {
                self.withLock {
                    self.reconnectAttempt = 0
                    self.isConnecting = false
                }
                self.flushPendingFrames()
            } else {
                self.scheduleReconnect()
            }
        }
        listenLoop()
    }

    func disconnect() {
        withLock {
            disconnectedManually = true
            task?.cancel(with: .goingAway, reason: nil)
            task = nil
            isConnecting = false
            responseHandlers.removeAll()
            pendingFrames.removeAll()
        }
    }

    @discardableResult
    func send(target: String, arguments: [Any] = [], onResponse: ((Any) -> Void)? = nil) -> Bool {
        let invocationId = UUID().uuidString
        if let onResponse {
            withLock {
                responseHandlers[invocationId] = onResponse
            }
        }

        let payload: [String: Any] = [
            "type": 1,
            "invocationId": invocationId,
            "target": target,
            "arguments": arguments
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return false }
        let frame = text + eof

        guard let task = withLock({ self.task }) else {
            withLock {
                pendingFrames.append(frame)
            }
            ensureConnected()
            return false
        }

        task.send(.string(frame)) { [weak self] error in
            guard let self, error != nil else { return }
            self.withLock {
                self.pendingFrames.append(frame)
            }
            self.scheduleReconnect()
        }
        return true
    }

    func sendAndWait(target: String, arguments: [Any] = []) async -> Any? {
        let invocationId = UUID().uuidString
        let payload: [String: Any] = [
            "type": 1,
            "invocationId": invocationId,
            "target": target,
            "arguments": arguments
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        let frame = text + eof

        return await withCheckedContinuation { continuation in
            let resumeLock = NSLock()
            var isResumed = false

            let finish: (Any?) -> Void = { result in
                resumeLock.lock()
                defer { resumeLock.unlock() }
                guard !isResumed else { return }
                isResumed = true
                continuation.resume(returning: result)
            }

            withLock {
                responseHandlers[invocationId] = { result in
                    finish(result)
                }
            }

            guard let task = withLock({ self.task }) else {
                withLock {
                    pendingFrames.append(frame)
                }
                ensureConnected()
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                    if let self {
                        self.withLock {
                            self.responseHandlers.removeValue(forKey: invocationId)
                        }
                    }
                    finish(nil)
                }
                return
            }

            task.send(.string(frame)) { [weak self] error in
                guard let self else { return }
                if error != nil {
                    self.withLock {
                        self.pendingFrames.append(frame)
                        self.responseHandlers.removeValue(forKey: invocationId)
                    }
                    self.scheduleReconnect()
                    finish(nil)
                }
            }
        }
    }

    private func listenLoop() {
        withLock({ self.task })?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                self.scheduleReconnect()
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
                let callbacks = withLock {
                    if let bucket = handlers[target] {
                        return Array(bucket.values)
                    }
                    return []
                }
                callbacks.forEach { $0(args) }
            case 2, 3:
                if let invocation = object["invocationId"] as? String {
                    let callback = withLock {
                        responseHandlers.removeValue(forKey: invocation)
                    }
                    callback?(object["result"] ?? [:])
                }
            default:
                break
            }
        }
    }

    private func ensureConnected() {
        let reconnectHeaders = withLock { () -> [String: String]? in
            guard !isConnecting, task == nil, !connectionHeaders.isEmpty else { return nil }
            return connectionHeaders
        }
        guard let reconnectHeaders else { return }
        connect(headers: reconnectHeaders)
    }

    private func scheduleReconnect() {
        let delay: Double? = withLock {
            guard !disconnectedManually else { return nil }
            task?.cancel(with: .goingAway, reason: nil)
            task = nil
            isConnecting = false
            reconnectAttempt += 1
            return min(pow(2.0, Double(max(0, reconnectAttempt - 1))), 8.0)
        }
        guard let delay else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.ensureConnected()
        }
    }

    private func flushPendingFrames() {
        let batch: (URLSessionWebSocketTask, [String])? = withLock {
            guard let task, !pendingFrames.isEmpty else { return nil }
            let frames = pendingFrames
            pendingFrames.removeAll()
            return (task, frames)
        }
        guard let (task, frames) = batch else { return }
        for frame in frames {
            task.send(.string(frame)) { [weak self] error in
                guard let self, error != nil else { return }
                self.withLock {
                    self.pendingFrames.append(frame)
                }
                self.scheduleReconnect()
            }
        }
    }

    @discardableResult
    private func withLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }
}
