import Foundation

/// `URLSessionWebSocketTask` over the server's `/ws`. The server (uvicorn) pings every 20 s and
/// URLSession answers automatically; our own ping both proves the socket is open after
/// `connect()` and detects half-open connections quickly.
public actor LiveGameSocket: GameSocket {
    private let url: URL
    private let session: URLSession
    private let pingInterval: Duration
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var isOpen = false
    private let stream: AsyncStream<SocketEvent>
    private let continuation: AsyncStream<SocketEvent>.Continuation

    public init(url: URL, session: URLSession = .shared, pingInterval: Duration = .seconds(20)) {
        self.url = url
        self.session = session
        self.pingInterval = pingInterval
        (stream, continuation) = AsyncStream.makeStream()
    }

    public var events: AsyncStream<SocketEvent> { stream }

    public func connect() async {
        if isOpen, task != nil { return }
        teardown()
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        do {
            try await Self.ping(task)
        } catch {
            fail(error)
            return
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
