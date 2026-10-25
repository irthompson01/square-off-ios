import Observation
import SquareOffCore
import SquareOffNet
import SwiftUI

/// Drives one local game: rules from SquareOffCore, CPU moves from a `CPUMoveProvider`, and
/// every move handed to a `GameRecorder` in order without ever waiting on it.
@Observable
final class GameSession: @MainActor GamePresenting {
    let id = UUID()
    let config: GameConfig
    private let cpu: any CPUMoveProvider
    private let recorder: any GameRecorder
    /// Where the unfinished game is persisted for "Continue" (nil in tests).
    private let store: LocalGameStore?
    /// CPU "think" time in milliseconds. The web waits `Math.random() * 1000 + 500`.
    private let thinkDelay: ClosedRange<Int>
    /// When the game was last written to the store (shown on the Continue card).
    private(set) var savedAt: Date?

    private(set) var game: Game
    private(set) var spins: [Cell: SpinEvent] = [:]
    private(set) var lastMove: MoveResult?
    private(set) var isCPUThinking = false
    private(set) var timeRemaining: Int?
    private(set) var turnDeadline: Date?
    var notice: String?
    var hiddenShapeOwners: Set<Int> = []
    var isGameOverPresented = false

    /// Bumped on every placement / scoring move; drives haptics.
    private(set) var placeCount = 0
    private(set) var scoreCount = 0

    private var spinSequence = 0
    private var timerTask: Task<Void, Never>?
    private var cpuTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    /// Recorder calls chained in order; the game never waits on them.
    private var recordingChain: Task<Void, Never>?

    init(
        config: GameConfig,
        cpu: any CPUMoveProvider = LocalCPUMoveProvider(),
        recorder: any GameRecorder = NoOpGameRecorder(),
        thinkDelay: ClosedRange<Int> = 500...1500,
        store: LocalGameStore? = nil
    ) {
        self.config = config
        self.cpu = cpu
        self.recorder = recorder
        self.thinkDelay = thinkDelay
        self.store = store
        self.game = Game(boardSize: config.boardSize, players: Self.seats(for: config), timerSeconds: config.timerSeconds)
        // The game exists from here on, so the recorder hears about it before any move can be
        // queued behind it (debug launch arguments tap before the screen appears).
        enqueueRecording { [recorder, game, config] in await recorder.gameStarted(game, config: config) }
        scheduleSave()
    }

    /// Rebuilds a saved game by replaying its moves. Not recorded to the server (the web's
    /// resume makes no new `/start` call either). Nil if the moves don't replay cleanly.
    init?(restoring snapshot: LocalGameStore.Snapshot, cpu: any CPUMoveProvider = LocalCPUMoveProvider(),
          thinkDelay: ClosedRange<Int> = 500...1500, store: LocalGameStore? = nil) {
        self.config = snapshot.config
        self.cpu = cpu
        self.recorder = NoOpGameRecorder()
        self.thinkDelay = thinkDelay
        self.store = store
        var game = Game(boardSize: snapshot.config.boardSize, players: Self.seats(for: snapshot.config), timerSeconds: snapshot.config.timerSeconds)
        for cell in snapshot.moves {
            guard (try? game.place(at: cell)) != nil else { return nil }
        }
        self.game = game
        self.savedAt = snapshot.savedAt
    }

    var isOver: Bool { game.isOver }
    var currentPlayer: PlayerState { game.currentPlayer }
    var canTap: Bool { !isOver && !currentPlayer.isCPU && !isCPUThinking }
    var title: String { config.title }
    var timerSeconds: Int { config.timerSeconds }
    var capabilities: GameCapabilities { GameCapabilities() }
    var rematchState: RematchState { .none }
    var connectionLabel: String? { nil }
    var mySeatID: Int? { nil }
    var role: OnlineRole? { nil }
    var spectatorCount: Int { 0 }
    var awaySeats: Set<Int> { [] }
    var statusBanner: StatusBanner? { nil }

    /// "Blue wins · 28 pts" / "Tie game" (web `GameOverModal`).
    var winnerHeadline: String {
        guard isOver else { return "Scores so far" }
        if game.isDraw { return "Tie game" }
        let winner = game.standings[0]
        return "\(winner.name) wins · \(winner.score) pts"
    }

    /// Shapes in the order they were formed, minus any owner the player has hidden.
    var visibleShapes: [BoardShape] {
        shapeHistory.filter { !hiddenShapeOwners.contains($0.ownerID) }
    }

    var shapeHistory: [BoardShape] { game.moves.flatMap(\.newShapes) }

    /// "Player 1's turn" for every seat, like the web's local `TurnBanner`.
    var turnLabel: String {
        if isOver { return game.isDraw ? "Game over · Tie game" : "Game over · \(game.standings[0].name) wins" }
        return "\(currentPlayer.name)'s turn"
    }

    // MARK: Lifecycle

    /// Safe to call every time the game screen appears: the current turn (CPU think or timer)
    /// resumes. Recording started in `init`.
    func start() async {
        startTurn()
    }

    func startRematch() { restart() }

    func leave() {
        stop()
        saveTask?.cancel()
        store?.clear()
    }

    /// Writes the game now (scene going to the background).
    func saveNow() {
        saveTask?.cancel()
        persist()
    }

    private func scheduleSave() {
        guard store != nil else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            persist()
        }
    }

    private func persist() {
        guard let store else { return }
        if game.isOver {
            store.clear()
            return
        }
        let snapshot = LocalGameStore.Snapshot(config: config, moves: game.moves.map(\.cell), savedAt: .now)
        store.save(snapshot)
        savedAt = snapshot.savedAt
    }

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
        turnDeadline = nil
        isGameOverPresented = false
        scheduleSave()
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
        turnDeadline = nil
        let mover = currentPlayer
        guard let result = try? game.place(at: cell) else { return }

        spinSequence += 1
        let events = SpinSchedule.events(for: result, sequence: spinSequence, continuousIndex: false)
        for (tile, event) in events {
            spins[tile] = event
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

        scheduleSave()
        if game.isOver {
            enqueueRecording { [recorder, game] in await recorder.gameEnded(game) }
            // Let the last tile's flip and spins finish before the sheet covers them.
            let delay = SpinSchedule.resultsDelay(for: events, reduceMotion: UIAccessibility.isReduceMotionEnabled)
            Task {
                try? await Task.sleep(for: .seconds(delay))
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
        // The answer only counts for the turn it was asked for: a restart, reset or resumed
        // game while the provider was thinking must not place a stale (or second) tile.
        let turnKey = (moves: game.moves.count, player: currentPlayer.id)
        var cell = await cpu.move(for: game, level: level)
        guard !Task.isCancelled, game.moves.count == turnKey.moves, currentPlayer.id == turnKey.player,
              !game.isOver else { return }
        // An unplayable reply (occupied, or off the board from a misbehaving server) becomes a
        // random empty tile, like the web's fallback; `Board[cell]` would trap out of range.
        if !game.board.contains(cell) || game.board[cell] != nil,
           let fallback = game.board.emptyCells.randomElement() {
            cell = fallback
        }
        isCPUThinking = false
        apply(cell)
    }

    private func startTimer() {
        guard config.timerSeconds > 0 else { return }
        timeRemaining = config.timerSeconds
        turnDeadline = .now + TimeInterval(config.timerSeconds)
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
                PlayerState(id: 2, name: "CPU (\(level.rawValue))", colorHex: cpuColor, isCPU: true, cpuLevel: level),
            ]
        case .passAndPlay:
            return config.players.map { PlayerState(id: $0.id, name: $0.name, colorHex: $0.colorHex) }
        }
    }
}
