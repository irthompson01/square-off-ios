import Foundation
import SquareOffCore
import SquareOffNet

/// Asks the server for the move (`POST /cpu_move`) for the levels in `serverLevels` and plays
/// on device for the rest. Any failure, timeout or illegal reply falls back to the local
/// heuristic for that level and tells the player once.
nonisolated struct ServerCPUMoveProvider: CPUMoveProvider {
    let api: any SquareOffAPI
    let serverLevels: Set<CPULevel>
    let notices: SessionNoticeRelay
    var timeout: Duration = .seconds(8)
    private let fallback = LocalCPUMoveProvider()

    init(api: any SquareOffAPI, serverLevels: Set<CPULevel>, notices: SessionNoticeRelay, timeout: Duration = .seconds(8)) {
        self.api = api
        self.serverLevels = serverLevels
        self.notices = notices
        self.timeout = timeout
    }

    func move(for game: Game, level: CPULevel) async -> Cell {
        guard serverLevels.contains(level) else { return await fallback.move(for: game, level: level) }
        do {
            let reply = try await withTimeout(timeout) { try await api.cpuMove(CPUMoveRequest(gameID: 0, game: game)) }
            guard (0..<game.board.size).contains(reply.row), (0..<game.board.size).contains(reply.col),
                  game.board[reply.cell] == nil else { throw APIError.invalidResponse }
            return reply.cell
        } catch {
            #if DEBUG
            print("[ServerCPUMoveProvider] falling back to on-device level \(level.offlineFallback.number): \(error)")
            #endif
            await notices.post(level == .cnn
                ? "Level 3 unavailable, using Level \(CPULevel.cnn.offlineFallback.number) on device"
                : "Server CPU unavailable, playing on device")
            return await fallback.move(for: game, level: level)
        }
    }
}

nonisolated func withTimeout<T: Sendable>(_ duration: Duration, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw APIError.timeout
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
