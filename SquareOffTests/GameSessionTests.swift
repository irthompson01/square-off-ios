import SquareOffCore
import Testing
@testable import SquareOff

/// Hands out scripted cells so tests know exactly where the CPU will play.
actor ScriptedCPU: CPUMoveProvider {
    private var queue: [Cell]
    private(set) var requests = 0

    init(_ cells: [Cell]) { queue = cells }

    func move(for game: Game, level: CPULevel) async -> Cell {
        requests += 1
        return queue.isEmpty ? game.board.emptyCells[0] : queue.removeFirst()
    }
}

/// Records what the session hands to the recorder, in order.
actor RecordingRecorder: GameRecorder {
    private(set) var events: [String] = []

    func gameStarted(_ game: Game, config: GameConfig) async { events.append("started") }
    func record(_ move: MoveResult, by player: PlayerState) async {
        events.append("move \(player.id) \(move.cell.row),\(move.cell.col)")
    }
    func gameEnded(_ game: Game) async { events.append("ended") }
}

@MainActor
struct GameSessionTests {
    private func cpuConfig() -> GameConfig {
        GameConfig(mode: .cpu(.maxMin), boardSize: 6, timerSeconds: 0,
                   players: [SetupPlayer(id: 1, name: "Me", colorHex: Theme.playerColors[0])])
    }

    private func waitForMoves(_ count: Int, in session: GameSession) async throws {
        for _ in 0..<60 where session.game.moves.count < count {
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(100))
    }

    @Test func cpuTurnUsesTheProviderAndRecordsInOrder() async throws {
        let cpu = ScriptedCPU([Cell(row: 5, col: 5)])
        let recorder = RecordingRecorder()
        let session = GameSession(config: cpuConfig(), cpu: cpu, recorder: recorder, thinkDelay: 0...0)
        await session.start()

        session.tap(Cell(row: 0, col: 0))
        try await waitForMoves(2, in: session)

        #expect(session.game.moves.count == 2)
        #expect(session.game.moves[1].cell == Cell(row: 5, col: 5))
        #expect(session.game.board[Cell(row: 5, col: 5)] == 2)
        #expect(await cpu.requests == 1)
        #expect(await recorder.events == ["started", "move 1 0,0", "move 2 5,5"])
    }

    @Test func tappingIsIgnoredDuringCPUTurn() async throws {
        let session = GameSession(config: cpuConfig(), cpu: ScriptedCPU([]), thinkDelay: 200...200)
        await session.start()
        session.tap(Cell(row: 0, col: 0))
        session.tap(Cell(row: 0, col: 1))
        #expect(session.game.moves.count == 1)
        session.stop()
    }

    @Test func plainPlacementFlipsWithoutSpinning() async throws {
        let config = GameConfig(mode: .passAndPlay, boardSize: 6, players: [
            SetupPlayer(id: 1, name: "A", colorHex: Theme.playerColors[0]),
            SetupPlayer(id: 2, name: "B", colorHex: Theme.playerColors[1]),
        ])
        let session = GameSession(config: config)
        await session.start()
        session.tap(Cell(row: 2, col: 3))
        #expect(session.spins[Cell(row: 2, col: 3)] == nil)
        #expect(session.lastMove?.cell == Cell(row: 2, col: 3))
        #expect(session.placeCount == 1)
    }

    @Test func localCPUPlaysALegalMoveOffline() async throws {
        let session = GameSession(config: cpuConfig(), thinkDelay: 0...0)
        await session.start()
        session.tap(Cell(row: 0, col: 0))
        try await waitForMoves(2, in: session)

        #expect(session.game.moves.count == 2)
        #expect(session.game.moves[1].playerID == 2)
        #expect(session.game.currentPlayer.id == 1)
        #expect(session.canTap)
    }

    @Test func occupiedCPUReplyPlaysARandomEmptyCell() async throws {
        // The human takes (0,0); the scripted CPU answers with the same tile.
        let session = GameSession(config: cpuConfig(), cpu: ScriptedCPU([Cell(row: 0, col: 0)]), thinkDelay: 0...0)
        await session.start()
        session.tap(Cell(row: 0, col: 0))
        try await waitForMoves(2, in: session)
        #expect(session.game.moves.count == 2)
        #expect(session.game.board[Cell(row: 0, col: 0)] == 1)
        #expect(session.game.moves.last?.playerID == 2)
    }

    @Test func outOfRangeCPUReplyDoesNotTrap() async throws {
        let session = GameSession(config: cpuConfig(), cpu: ScriptedCPU([Cell(row: 99, col: 0)]), thinkDelay: 0...0)
        await session.start()
        session.tap(Cell(row: 2, col: 2))
        try await waitForMoves(2, in: session)
        #expect(session.game.moves.count == 2)
        #expect(session.game.board.contains(session.game.moves.last!.cell))
    }

    @Test func restartWhileCPUIsThinkingDiscardsTheStaleMove() async throws {
        let session = GameSession(config: cpuConfig(), cpu: ScriptedCPU([Cell(row: 5, col: 5)]), thinkDelay: 150...150)
        await session.start()
        session.tap(Cell(row: 0, col: 0))
        try await Task.sleep(for: .milliseconds(30))
        session.restart()
        try await Task.sleep(for: .milliseconds(400))

        #expect(session.game.moves.isEmpty)
        #expect(session.game.board[Cell(row: 5, col: 5)] == nil)
        #expect(session.canTap)
        session.stop()
    }
}
