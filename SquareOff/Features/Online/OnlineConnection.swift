import Foundation
import SquareOffNet

/// One socket with one long-lived pump that forwards events to whoever currently owns the
/// room: the `RoomCoordinator` while in the lobby, then the `OnlineGameSession`. Handing over
/// is a property assignment, so no event is lost and the stream has a single consumer.
@MainActor
final class OnlineConnection {
    let socket: any GameSocket
    var onEvent: ((SocketEvent) -> Void)?
    private(set) var isConnected = false
    private var pump: Task<Void, Never>?

    init(socket: any GameSocket) {
        self.socket = socket
    }

    func connect() async throws {
        if pump == nil {
            let socket = socket
            pump = Task { [weak self] in
                for await event in await socket.events {
                    guard let self else { return }
                    self.dispatch(event)
                }
            }
        }
        try await socket.connect()
        isConnected = true
    }

    func send(_ message: ClientMessage) async throws {
        try await socket.send(message)
    }

    func close() async {
        pump?.cancel()
        pump = nil
        isConnected = false
        await socket.close()
    }

    /// Retries `connect()` with backoff (0.5 s doubling to 8 s) until `deadline`, then runs
    /// `afterConnect` (typically `REJOIN_ROOM`). Returns false when the window closes.
    func reconnect(until deadline: ContinuousClock.Instant,
                   onAttempt: @MainActor (Int) -> Void = { _ in },
                   afterConnect: @MainActor () async throws -> Void) async -> Bool {
        var attempt = 1
        var delay: Duration = .milliseconds(500)
        while ContinuousClock.now < deadline, !Task.isCancelled {
            onAttempt(attempt)
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return false }
            do {
                try await connect()
                try await afterConnect()
                return true
            } catch {
                attempt += 1
                delay = min(delay * 2, .seconds(8))
            }
        }
        return false
    }

    private func dispatch(_ event: SocketEvent) {
        if case .disconnected = event { isConnected = false }
        if case .connected = event { isConnected = true }
        onEvent?(event)
    }
}

/// Everything the lobby and the game need from the chosen backend.
struct OnlineTransport {
    let connection: OnlineConnection
    let matcher: any MatcherAPI
    let api: any SquareOffAPI
    /// Web client origin for invite links (`/guest/<code>`).
    let inviteBase: URL
    /// Guards persisted room sessions against a backend switch.
    let backendID: String

    func inviteURL(code: Int) -> URL { inviteBase.appending(path: "guest/\(code)") }
}

/// The room this device was in, for `REJOIN_ROOM` after a relaunch within the grace window.
nonisolated struct OnlineSessionRecord: Codable, Equatable, Sendable {
    static let key = "onlineSession"

    var roomCode: Int
    var seat: Int?
    var role: OnlineRole
    var gameID: Int?
    var boardSize: Int
    var timerSeconds: Int
    var started: Bool
    var savedAt: Date
    var backendID: String

    /// Host rooms survive 60 s without their host, guest seats 30 s.
    var graceSeconds: TimeInterval { role == .host ? 60 : 30 }
    var isWithinGrace: Bool { Date().timeIntervalSince(savedAt) < graceSeconds }

    static func load(defaults: UserDefaults = .standard) -> OnlineSessionRecord? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(OnlineSessionRecord.self, from: data)
    }

    func save(defaults: UserDefaults = .standard) {
        var copy = self
        copy.savedAt = Date()
        defaults.set(try? JSONEncoder().encode(copy), forKey: Self.key)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
