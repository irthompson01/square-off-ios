import Observation
import SquareOffCore
import SwiftUI

/// A spin request for one tile. `id` changes every time so the same tile can spin again.
/// The rules say corners spin `2 × shapes` turns, accumulating when a tile belongs to several
/// shapes; on a 12×12 with a big multiplier that is many seconds of spinning, so the view caps it.
struct SpinEvent: Equatable {
    static let maxTurns = 3

    let id: Int
    let turns: Int

    init(id: Int, turns: Int) {
        self.id = id
        self.turns = min(max(turns, 1), Self.maxTurns)
    }
}

/// Drives one local game: rules from SquareOffCore, CPU moves from a `CPUMoveProvider`, and
/// every move handed to a `GameRecorder` in order without ever waiting on it.
@Observable
final class GameSession: @MainActor GamePresenting {
    let id = UUID()
    let config: GameConfig
    private let cpu: any CPUMoveProvider
    private let recorder: any GameRecorder
    /// CPU "think" time in milliseconds. The web waits `Math.random() * 1000 + 500`.
    private let thinkDelay: ClosedRange<Int>

    private(set) var game: Game
    private(set) var spins: [Cell: SpinEvent] = [:]
    private(set) var lastMove: MoveResult?
    private(set) var isCPUThinking = false
    private(set) var timeRemaining: Int?
    var notice: String?
    var hiddenShapeOwners: Set<Int> = []
    var isGameOverPresented = false

    /// Bumped on every placement / scoring move; drives haptics.
    private(set) var placeCount = 0
    private(set) var scoreCount = 0

    private var spinSequence = 0
    private var timerTask: Task<Void, Never>?
    private var cpuTask: Task<Void, Never>?
    /// Recorder calls chained in order; the game never waits on them.
    private var recordingChain: Task<Void, Never>?

    init(
        config: GameConfig,
        cpu: any CPUMoveProvider = LocalCPUMoveProvider(),
        recorder: any GameRecorder = NoOpGameRecorder(),
        thinkDelay: ClosedRange<Int> = 500...1500
    ) {
        self.config = config
        self.cpu = cpu
        self.recorder = recorder
        self.thinkDelay = thinkDelay
        self.game = Game(boardSize: config.boardSize, players: Self.seats(for: config), timerSeconds: config.timerSeconds)
        // The game exists from here on, so the recorder hears about it before any move can be
        // queued behind it (debug launch arguments tap before the screen appears).
        enqueueRecording { [recorder, game, config] in await recorder.gameStarted(game, config: config) }
    }

    var isOver: Bool { game.isOver }
    var currentPlayer: PlayerState { game.currentPlayer }
    var canTap: Bool { !isOver && !currentPlayer.isCPU && !isCPUThinking }
    var title: String { config.title }
    var timerSeconds: Int { config.timerSeconds }
    var capabilities: GameCapabilities { GameCapabilities() }
    var rematchState: RematchState { .none }
    var connectionLabel: String? { nil }

    var winnerHeadline: String {
        guard isOver else { return "Scores so far" }
        if game.isDraw { return "Tie game" }
        let winner = game.standings[0]
        if case .cpu = config.mode { return winner.isCPU ? "CPU wins" : "You win" }
        return "\(winner.name) wins"
    }

    /// Shapes in the order they were formed, minus any owner the player has hidden.
    var visibleShapes: [BoardShape] {
        game.moves.flatMap(\.newShapes).filter { !hiddenShapeOwners.contains($0.ownerID) }
    }

    var turnLabel: String {
        if isOver { return game.isDraw ? "Tie game" : "\(game.standings[0].name) wins" }
        if currentPlayer.isCPU { return "CPU is thinking…" }
        if case .cpu = config.mode { return "Your turn" }
        return "\(currentPlayer.name)'s turn"
    }

    // MARK: Lifecycle

    /// Safe to call every time the game screen appears: the current turn (CPU think or timer)
    /// resumes. Recording started in `init`.
    func start() async {
        startTurn()
    }

    func startRematch() { restart() }

    func leave() { stop() }

    private func enqueueRecording(_ operation: @escaping @Sendable () async -> Void) {
        recordingChain = Task { [previous = recordingChain] in
            await previous?.value
            await operation()
        }
    }

    func restart() {
        timerTask?.cancel()
        cpuTask?.cancel()
        isCPUThinking = false
        game = Game(boardSize: config.boardSize, players: Self.seats(for: config), timerSeconds: config.timerSeconds)
        enqueueRecording { [recorder, game, config] in await recorder.gameStarted(game, config: config) }
        spins = [:]
        lastMove = nil
        timeRemaining = nil
        isGameOverPresented = false
        Task { await start() }
    }

    func stop() {
        timerTask?.cancel()
        cpuTask?.cancel()
    }

    // MARK: Moves

    func tap(_ cell: Cell) {
        guard canTap, game.board[cell] == nil else { return }
        apply(cell)
    }

    private func apply(_ cell: Cell) {
        timerTask?.cancel()
        let mover = currentPlayer
        guard let result = try? game.place(at: cell) else { return }

        spinSequence += 1
        for (tile, turns) in result.spinTurns {
            spins[tile] = SpinEvent(id: spinSequence, turns: turns)
        }
        lastMove = result
        placeCount += 1
        if result.newShapeCount > 0 {
            scoreCount += 1
            SoundPlayer.shared.play(.spin)
        } else {
            SoundPlayer.shared.play(.place)
        }

        let updatedMover = game.players.first { $0.id == mover.id } ?? mover
        enqueueRecording { [recorder] in await recorder.record(result, by: updatedMover) }

        if game.isOver {
            enqueueRecording { [recorder, game] in await recorder.gameEnded(game) }
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                isGameOverPresented = true
            }
        } else {
            startTurn()
        }
    }

    private func startTurn() {
        guard !game.isOver else { return }
        cpuTask?.cancel()
        timerTask?.cancel()
        if currentPlayer.isCPU {
            cpuTask = Task { await playCPUTurn() }
        } else {
            startTimer()
        }
    }

    private func playCPUTurn() async {
        isCPUThinking = true
        defer { isCPUThinking = false }
        // Same feel as the web: the CPU never answers instantly.
        let delay = thinkDelay.lowerBound == thinkDelay.upperBound ? thinkDelay.lowerBound : Int.random(in: thinkDelay)
        if delay > 0 { try? await Task.sleep(for: .milliseconds(delay)) }
        guard !Task.isCancelled else { return }

        let level = currentPlayer.cpuLevel ?? .random
        var cell = await cpu.move(for: game, level: level)
        // A restart while thinking must not apply a stale move to the new board.
        guard !Task.isCancelled else { return }
        if game.board[cell] != nil, let fallback = game.board.emptyCells.randomElement() {
            cell = fallback
        }
        isCPUThinking = false
        apply(cell)
    }

    private func startTimer() {
        guard config.timerSeconds > 0 else { return }
        timeRemaining = config.timerSeconds
        timerTask = Task {
            while let remaining = timeRemaining, remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                timeRemaining = remaining - 1
            }
            // Time's up: play a random tile, like the web does for local games.
            if let cell = game.board.emptyCells.randomElement() { apply(cell) }
        }
    }

    private static func seats(for config: GameConfig) -> [PlayerState] {
        switch config.mode {
        case .cpu(let level):
            let me = config.players[0]
            let cpuColor = me.colorHex == Theme.playerColors[1] ? Theme.playerColors[0] : Theme.playerColors[1]
            // The seat keeps the chosen level; the move provider decides where it runs.
            return [
                PlayerState(id: 1, name: me.name, colorHex: me.colorHex),
                PlayerState(id: 2, name: "CPU · L\(level.number)", colorHex: cpuColor, isCPU: true, cpuLevel: level),
            ]
        case .passAndPlay:
            return config.players.map { PlayerState(id: $0.id, name: $0.name, colorHex: $0.colorHex) }
        }
    }
}
