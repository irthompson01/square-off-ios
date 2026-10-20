import SquareOffCore

/// Where a CPU seat's move comes from: on device (`LocalCPUMoveProvider`) or the server
/// (`ServerCPUMoveProvider`, used for the CNN level).
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

/// Receives the life of a game so it can be logged to the server (`ServerGameRecorder`:
/// `POST /start`, `POST /{id}/turns`, `PUT /end`). `GameSession` calls these strictly in order
/// and never waits for them.
nonisolated protocol GameRecorder: Sendable {
    func gameStarted(_ game: Game, config: GameConfig) async
    func record(_ move: MoveResult, by player: PlayerState) async
    func gameEnded(_ game: Game) async
}

nonisolated struct NoOpGameRecorder: GameRecorder {
    func gameStarted(_ game: Game, config: GameConfig) async {}
    func record(_ move: MoveResult, by player: PlayerState) async {}
    func gameEnded(_ game: Game) async {}
}
