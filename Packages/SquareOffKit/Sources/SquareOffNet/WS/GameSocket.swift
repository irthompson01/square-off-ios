import Foundation

public enum SocketEvent: Sendable {
    case connected
    case disconnected(Error?)
    case message(ServerMessage)
}

public enum SocketError: Error, Equatable {
    case notConnected
    case closed
}

/// A dumb transport to the game room server. Both the live `/ws` socket and the in-app
/// simulator implement it; reconnect policy (and `REJOIN_ROOM`) lives in the consumer because
/// only it knows the room, seat and role.
///
/// `events` has a single consumer and survives reconnects: `connect()` after a drop yields a
/// fresh `.connected` on the same stream.
public protocol GameSocket: Sendable {
    var events: AsyncStream<SocketEvent> { get async }
    /// Idempotent. Yields `.connected`, or `.disconnected(error)` when the handshake fails.
    func connect() async
    func send(_ message: ClientMessage) async throws
    /// Deliberate close: no `.disconnected` event follows.
    func close() async
}
