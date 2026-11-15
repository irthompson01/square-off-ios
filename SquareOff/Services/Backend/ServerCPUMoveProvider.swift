import Foundation
import SquareOffCore
import SquareOffNet

/// Asks the server for the move (`POST /cpu_move`) for the levels in `serverLevels` and plays
/// on device for the rest. Any failure, timeout or illegal reply falls back to the local
/// stand-in for that level (`offlineFallback`) and tells the player once; after two failures in
/// a row the rest of the game stays on device instead of waiting out the timeout every turn.
/// A server that had to substitute a simpler engine itself (`engine.fallback`) is mentioned
/// once per game too.
nonisolated struct ServerCPUMoveProvider: CPUMoveProvider {
    /// Consecutive failures for this game; one provider is made per game (`Backend.makeCPUProvider`).
    actor FailureCounter {
        private var consecutive = 0
        var isOpen: Bool { consecutive >= 2 }
        func failed() { consecutive += 1 }
        func succeeded() { consecutive = 0 }
    }

    let api: any SquareOffAPI
    let serverLevels: Set<CPULevel>
    let notices: SessionNoticeRelay
    /// The web gives up after 8 s; the engine tiers answer within their 0.4 × timer budget.
    var timeout: Duration = .seconds(8)
    private let fallback = LocalCPUMoveProvider()
    private let failures = FailureCounter()

    init(api: any SquareOffAPI, serverLevels: Set<CPULevel>, notices: SessionNoticeRelay, timeout: Duration = .seconds(8)) {
        self.api = api
        self.serverLevels = serverLevels
        self.notices = notices
        self.timeout = timeout
    }

    func move(for game: Game, level: CPULevel) async -> Cell {
        guard serverLevels.contains(level) else { return await fallback.move(for: game, level: level) }
        if await failures.isOpen { return await fallback.move(for: game, level: level) }
        do {
            let reply = try await withTimeout(timeout) { try await api.cpuMove(CPUMoveRequest(gameID: 0, game: game)) }
            guard (0..<game.board.size).contains(reply.row), (0..<game.board.size).contains(reply.col),
                  game.board[reply.cell] == nil else { throw APIError.invalidResponse }
            await failures.succeeded()
            if reply.isEngineFallback {
                await notices.postOnce(key: "engine-fallback", "Server engine busy, playing a simpler move")
            }
            return reply.cell
        } catch {
            #if DEBUG
            print("[ServerCPUMoveProvider] falling back to on-device level \(level.offlineFallback.number): \(error)")
            #endif
            await failures.failed()
            let stand = level.offlineFallback
            await notices.postOnce(key: "cpu-fallback-\(level.number)", level == stand
                ? "Server CPU unavailable, playing on device"
                : "Level \(level.number) unavailable, using Level \(stand.number) on device")
            return await fallback.move(for: game, level: level)
        }
    }
}
