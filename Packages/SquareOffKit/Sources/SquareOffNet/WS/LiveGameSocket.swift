import Foundation

/// `URLSessionWebSocketTask` over the server's `/ws`. The handshake carries the session token
/// (`Authorization: Bearer`, read from the provider at connect time so a renewed guest token
/// or a fresh sign-in is picked up on reconnect). The server (uvicorn) pings every 20 s and
/// URLSession answers automatically; our own ping both proves the socket is open after
/// `connect()` and detects half-open connections quickly.
public actor LiveGameSocket: GameSocket {
    private let url: URL
    private let session: URLSession
    private let tokenProvider: (any TokenProvider)?
    private let pingInterval: Duration
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var isOpen = false
    private let stream: AsyncStream<SocketEvent>
    private let continuation: AsyncStream<SocketEvent>.Continuation

    public init(url: URL, session: URLSession = .shared, tokenProvider: (any TokenProvider)? = nil,
                pingInterval: Duration = .seconds(20)) {
        self.url = url
        self.session = session
        self.tokenProvider = tokenProvider
        self.pingInterval = pingInterval
        (stream, continuation) = AsyncStream.makeStream()
    }

    public var events: AsyncStream<SocketEvent> { stream }

    public func connect() async throws {
        if isOpen, task != nil { return }
        teardown()
        var request = URLRequest(url: url)
        if let token = tokenProvider?.accessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        do {
            try await Self.ping(task)
        } catch {
            let refusal = Self.refusal(of: task, error: error)
            teardown()
            throw refusal ?? error
        }
        isOpen = true
        continuation.yield(.connected)
        receiveTask = Task { await self.receiveLoop(task) }
        pingTask = Task { await self.pingLoop(task) }
    }

    public func send(_ message: ClientMessage) async throws {
        guard let task, isOpen else { throw SocketError.notConnected }
        let text = String(decoding: try message.encoded(), as: UTF8.self)
        try await task.send(.string(text))
    }

    public func close() async {
        isOpen = false
        teardown(closeCode: .normalClosure)
    }

    // MARK: Handshake failures

    /// A refused upgrade as `SocketError.handshakeRefused`, or nil for an ordinary network error.
    /// The server closes with 1008 (policy violation) or 1013 (try again later) before accepting;
    /// URLSession may surface that as the close code or only as a bad server response.
    private static func refusal(of task: URLSessionWebSocketTask, error: Error) -> SocketError? {
        let code = task.closeCode.rawValue
        let reason = task.closeReason.flatMap { String(data: $0, encoding: .utf8) }
        if code == 1008 || code == 1013 {
            return .handshakeRefused(code: code, reason: reason?.isEmpty == false ? reason : nil)
        }
        if let urlError = error as? URLError, urlError.code == .badServerResponse {
            return .handshakeRefused(code: nil, reason: nil)
        }
        return nil
    }

    // MARK: Loops

    private func receiveLoop(_ task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let incoming = try await task.receive()
                let data: Data
                switch incoming {
                case let .string(text): data = Data(text.utf8)
                case let .data(bytes): data = bytes
                @unknown default: continue
                }
                do {
                    continuation.yield(.message(try ServerMessage.decode(data)))
                } catch {
                    #if DEBUG
                    print("[LiveGameSocket] undecodable message: \(error)")
                    #endif
                }
            } catch {
                if !Task.isCancelled { fail(error) }
                return
            }
        }
    }

    private func pingLoop(_ task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: pingInterval)
            guard !Task.isCancelled else { return }
            do {
                try await Self.ping(task)
            } catch {
                if !Task.isCancelled { fail(error) }
                return
            }
        }
    }

    private static func ping(_ task: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error { c.resume(throwing: error) } else { c.resume() }
            }
        }
    }

    private func fail(_ error: Error) {
        let wasOpen = isOpen || task != nil
        isOpen = false
        teardown(closeCode: .goingAway)
        if wasOpen { continuation.yield(.disconnected(error)) }
    }

    private func teardown(closeCode: URLSessionWebSocketTask.CloseCode = .goingAway) {
        receiveTask?.cancel()
        pingTask?.cancel()
        receiveTask = nil
        pingTask = nil
        task?.cancel(with: closeCode, reason: nil)
        task = nil
    }
}
