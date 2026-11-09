import Foundation

/// A `GameSocket` whose other end is the in-process `MockRoomServer`. `playerID` stands for the
/// session token the live socket sends on the handshake: the server stamps it on the seat.
public actor MockGameSocket: GameSocket {
    private let server: MockRoomServer
    private let playerID: String?
    private var connectionID: MockRoomServer.ConnectionID?
    private var forwardTask: Task<Void, Never>?
    private var refusals: [SocketError] = []
    private let stream: AsyncStream<SocketEvent>
    private let continuation: AsyncStream<SocketEvent>.Continuation

    public init(server: MockRoomServer, playerID: String? = nil) {
        self.server = server
        self.playerID = playerID
        (stream, continuation) = AsyncStream.makeStream()
    }

    public var events: AsyncStream<SocketEvent> { stream }

    public func connect() async throws {
        if connectionID != nil { return }
        if !refusals.isEmpty { throw refusals.removeFirst() }
        let (id, messages) = await server.connect(playerID: playerID)
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

    /// Test hook: the next `connect()` fails the way the live server refuses a handshake.
    public func refuseNextConnect(code: Int? = 1008, reason: String? = "session_required") {
        refusals.append(.handshakeRefused(code: code, reason: reason))
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
