import SquareOffCore

/// Where a CPU seat's move comes from. v1 computes it on device; a server-backed provider
/// (`POST /cpu_move`) can slot in here later without touching the screens.
nonisolated protocol CPUMoveProvider: Sendable {
    func move(for game: Game, level: CPULevel) async -> Cell
}

/// Runs `SquareOffCore`'s port of the server heuristics off the main actor.
nonisolated struct LocalCPUMoveProvider: CPUMoveProvider {
    func move(for game: Game, level: CPULevel) async -> Cell {
        let strategy = CPUStrategy(level: level.offlineFallback) ?? .random
        // `Game` and `CPUStrategy` are Sendable value types, so nothing isolated crosses the hop.
        return await Task.detached(priority: .userInitiated) { strategy.chooseMove(in: game) }.value
    }
}

/// Receives every move so a later pass can log games to the server (`POST /start`,
/// `POST /{id}/turns`) or to local storage. v1 keeps nothing.
nonisolated protocol GameRecorder: Sendable {
    func gameStarted(_ game: Game, config: GameConfig) async
    func record(_ move: MoveResult, by player: PlayerState) async
}

nonisolated struct NoOpGameRecorder: GameRecorder {
    func gameStarted(_ game: Game, config: GameConfig) async {}
    func record(_ move: MoveResult, by player: PlayerState) async {}
}
