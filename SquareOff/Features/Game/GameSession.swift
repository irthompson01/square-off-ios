import Observation
import SquareOffCore
import SquareOffNet
import SwiftUI

/// A spin request for one tile. `id` changes every time so the same tile can spin again.
struct SpinEvent: Equatable {
    let id: Int
    let turns: Int
}

/// Drives one game: local rules from SquareOffCore, server calls in the same order as the web
/// (`/guests` + `/cpu_player` → `/start` → `/{id}/turns` per move, `/cpu_move` on CPU turns).
@Observable
final class GameSession: Identifiable {
    let id = UUID()
    let config: GameConfig
    private let api: any SquareOffAPI

    private(set) var game: Game
    private(set) var serverGameID: Int?
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

    init(config: GameConfig, api: any SquareOffAPI, account: Account) {
        self.config = config
        self.api = api
        self.game = Game(boardSize: config.boardSize, players: Self.seats(for: config), timerSeconds: config.timerSeconds)
    }

    var isOver: Bool { game.isOver }
    var currentPlayer: PlayerState { game.currentPlayer }
    var canTap: Bool { !isOver && !currentPlayer.isCPU && !isCPUThinking }

    var visibleShapes: [BoardShape] {
        game.allShapes.filter { !hiddenShapeOwners.contains($0.ownerID) }
    }

    var turnLabel: String {
        if isOver { return game.isDraw ? "Tie game" : "\(game.standings[0].name) wins" }
        if currentPlayer.isCPU { return "CPU is thinking…" }
        if case .cpu = config.mode { return "Your turn" }
        return "\(currentPlayer.name)'s turn"
    }

    // MARK: Lifecycle

    func start() async {
        do {
            try await registerWithServer()
        } catch {
            notice = "Couldn't reach the server. This game won't be saved."
        }
        startTurn()
    }

    func restart() {
        timerTask?.cancel()
        game = Game(boardSize: config.boardSize, players: Self.seats(for: config), timerSeconds: config.timerSeconds)
        serverGameID = nil
        spins = [:]
        lastMove = nil
        isGameOverPresented = false
        Task { await start() }
    }

    func stop() {
        timerTask?.cancel()
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

        recordTurn(result, mover: game.players.first { $0.id == mover.id } ?? mover)

        if game.isOver {
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
        if currentPlayer.isCPU {
            Task { await playCPUTurn() }
        } else {
            startTimer()
        }
    }

    private func playCPUTurn() async {
        isCPUThinking = true
        defer { isCPUThinking = false }
        // Same feel as the web: the CPU never answers instantly.
        try? await Task.sleep(for: .milliseconds(650))
        let request = CPUMoveRequest(gameID: serverGameID ?? 0, game: game)
        var cell: Cell
        do {
            cell = try await api.cpuMove(request).cell
        } catch {
            // The web stalls here; we keep the game going and say why.
            notice = "CPU server error (\(currentPlayer.cpuLevel?.shortName ?? "CPU")). Played a random move."
            cell = game.board.emptyCells.randomElement() ?? Cell(row: 0, col: 0)
        }
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
            // Time's up: play a random tile, like the online server does on TURN_COMPLETE.
            if let cell = game.board.emptyCells.randomElement() { apply(cell) }
        }
    }

    // MARK: Server

    private func registerWithServer() async throws {
        let guests = try await api.guests().guests
        var players = game.players
        var guestIndex = 0
        for i in players.indices {
            if let level = players[i].cpuLevel {
                let cpu = try await api.cpuPlayer(level)
                players[i].serverPlayerID = String(cpu.id)
            } else {
                players[i].serverPlayerID = guests.indices.contains(guestIndex) ? guests[guestIndex] : nil
                guestIndex += 1
            }
        }
        let response = try await api.startGame(
            StartGameRequest(boardSize: game.board.size, timer: config.timerSeconds, players: players, type: .local)
        )
        serverGameID = response.gameId
        var participants: [Int: Int] = [:]
        for (seat, participant) in zip(players, response.participants) {
            participants[seat.id] = participant.participantId
        }
        game = Game(boardSize: game.board.size, players: players.map { seat in
            var seat = seat
            seat.participantID = participants[seat.id]
            return seat
        }, timerSeconds: config.timerSeconds)
    }

    private func recordTurn(_ move: MoveResult, mover: PlayerState) {
        guard let gameID = serverGameID else { return }
        let request = GameTurnRequest(move: move, player: mover)
        Task { [api] in _ = try? await api.insertTurn(gameID: gameID, request) }
    }

    private static func seats(for config: GameConfig) -> [PlayerState] {
        switch config.mode {
        case .cpu(let level):
            let me = config.players[0]
            let cpuColor = me.colorHex == Theme.playerColors[1] ? Theme.playerColors[0] : Theme.playerColors[1]
            return [
                PlayerState(id: 1, name: me.name, colorHex: me.colorHex),
                PlayerState(id: 2, name: "CPU · L\(level.number)", colorHex: cpuColor, isCPU: true, cpuLevel: level),
            ]
        case .passAndPlay, .onlineMock:
            return config.players.map { PlayerState(id: $0.id, name: $0.name, colorHex: $0.colorHex) }
        }
    }
}
