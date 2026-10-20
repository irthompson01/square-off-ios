import Foundation

/// A `GameSocket` whose other end is the in-process `MockRoomServer`.
public actor MockGameSocket: GameSocket {
    private let server: MockRoomServer
    private var connectionID: MockRoomServer.ConnectionID?
    private var forwardTask: Task<Void, Never>?
    private let stream: AsyncStream<SocketEvent>
    private let continuation: AsyncStream<SocketEvent>.Continuation

    public init(server: MockRoomServer) {
        self.server = server
        (stream, continuation) = AsyncStream.makeStream()
    }

    public var events: AsyncStream<SocketEvent> { stream }

    public func connect() async {
        if connectionID != nil { return }
        let (id, messages) = await server.connect()
        connectionID = id
        let continuation = continuation
        forwardTask = Task {
            for await message in messages {
                continuation.yield(.message(message))
            }
        }
        continuation.yield(.connected)
    }

    public func send(_ message: ClientMessage) async throws {
        guard let connectionID else { throw SocketError.notConnected }
        await server.handle(message, from: connectionID)
    }

    public func close() async {
        await detach()
    }

    /// Test hook: the network died. The consumer sees `.disconnected` and may reconnect.
    public func simulateDrop() async {
        guard connectionID != nil else { return }
        await detach()
        continuation.yield(.disconnected(nil))
    }

    private func detach() async {
        forwardTask?.cancel()
        forwardTask = nil
        if let connectionID {
            await server.disconnect(connectionID)
        }
        connectionID = nil
    }
}
