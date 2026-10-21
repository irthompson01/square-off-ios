import Observation
import SquareOffCore
import SquareOffNet
import SwiftUI

/// A game in an online room. The server is authoritative: a tap only sends the cell, and the
/// echoed `GAME_UPDATE` is applied with the rules engine (which reproduces the server's scoring
/// exactly, so spins and sounds work as in local play). When an echo ever disagrees, the game
/// is rebuilt from the server's snapshot.
@Observable
@MainActor
final class OnlineGameSession: @MainActor GamePresenting {
    enum Phase: Equatable {
        case playing
        case over
        case awaitingRematch(hostReady: Bool)
        case roomClosed(String)
    }

    enum Connection: Equatable {
        case online
        case reconnecting(attempt: Int)
        case lost
    }

    let id = UUID()
    let roomCode: Int
    let timerSeconds: Int
    private(set) var boardSize: Int
    private(set) var onlineRole: OnlineRole
    private(set) var mySeat: Int?
    private(set) var game: Game
    private(set) var phase: Phase = .playing
    private(set) var connection: Connection = .online
    private(set) var awaySeats: Set<Int> = []
    private(set) var spectatorCount = 0
    private(set) var gameID: Int?
    private(set) var seats: [PlayerPayload]

    private(set) var spins: [Cell: SpinEvent] = [:]
    private(set) var lastMove: MoveResult?
    private(set) var timeRemaining: Int?
    private(set) var turnDeadline: Date?
    private(set) var hostAway = false
    var notice: String?
    var hiddenShapeOwners: Set<Int> = []
    var isGameOverPresented = false
    private(set) var placeCount = 0
    private(set) var scoreCount = 0

    private var shapeLog: [BoardShape]
    private var pendingCell: Cell?
    private var spinSequence = 0
    private var started = false
    private var endPosted = false
    private var timerTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var stallTask: Task<Void, Never>?
    private let transport: OnlineTransport
    private let me: Identity

    init?(transport: OnlineTransport, me: Identity, roomCode: Int, role: OnlineRole, seat: Int?,
          snapshot: GameSnapshotPayload, timerSeconds: Int, gameID: Int?) {
        guard let game = Game(restoring: snapshot, timerSeconds: timerSeconds) else { return nil }
        self.transport = transport
        self.me = me
        self.roomCode = roomCode
        self.onlineRole = role
        self.mySeat = seat
        self.game = game
        self.boardSize = game.board.size
        self.timerSeconds = timerSeconds
        self.gameID = gameID ?? snapshot.gameId
        self.seats = snapshot.seats
        self.spectatorCount = snapshot.spectatorCount ?? 0
        self.shapeLog = snapshot.gameState.allShapes
        if game.isOver { phase = .over }
        // Own the socket from now on: nothing between the lobby and the first frame is lost.
        transport.connection.onEvent = { [weak self] event in self?.handle(event) }
        saveRecord(started: true)
    }

    // MARK: GamePresenting

    var title: String { "Room \(roomCode) · \(boardSize)×\(boardSize)" }
    var isOver: Bool { game.isOver }
    var currentPlayer: PlayerState { game.currentPlayer }

    var isCPUThinking: Bool {
        phase == .playing && !game.isOver && onlineRole != .spectator && game.currentPlayer.id != mySeat
    }

    var canTap: Bool {
        phase == .playing && !game.isOver && onlineRole != .spectator
            && game.currentPlayer.id == mySeat && pendingCell == nil && connection == .online
    }

    var visibleShapes: [BoardShape] {
        shapeLog.filter { !hiddenShapeOwners.contains($0.ownerID) }
    }

    var shapeHistory: [BoardShape] { shapeLog }

    var turnLabel: String {
        switch phase {
        case .roomClosed(let reason): return reason
        case .awaitingRematch(let hostReady): return hostReady ? "Start the rematch when everyone's ready" : "Waiting for the host to start the rematch"
        case .over: return game.isDraw ? "Tie game" : "\(name(of: game.standings[0].id)) wins"
        case .playing: break
        }
        let mover = game.currentPlayer.id
        if awaySeats.contains(mover) { return "\(name(of: mover)) is away…" }
        if onlineRole == .spectator { return "Spectating · \(name(of: mover))'s turn" }
        return mover == mySeat ? "Your turn" : "\(name(of: mover))'s turn"
    }

    var winnerHeadline: String {
        guard game.isOver else { return "Scores so far" }
        if game.isDraw { return "Tie game" }
        let winner = game.standings[0]
        return "\(name(of: winner.id)) wins · \(winner.score) pts"
    }

    var capabilities: GameCapabilities {
        GameCapabilities(canRestart: onlineRole == .host, canReset: onlineRole == .host, isSpectator: onlineRole == .spectator, isOnline: true, roomCode: roomCode)
    }

    var mySeatID: Int? { mySeat }
    var role: OnlineRole? { onlineRole }

    var statusBanner: StatusBanner? {
        if case .roomClosed(let reason) = phase { return .error(reason) }
        if hostAway { return .hostAway }
        if connection != .online { return .connecting }
        return nil
    }

    var rematchState: RematchState {
        guard case .awaitingRematch = phase else { return .none }
        return onlineRole == .host ? .hostCanStart : .waitingForHost
    }

    var connectionLabel: String? {
        switch connection {
        case .online:
            if case .roomClosed = phase { return "Room closed" }
            return nil
        case .reconnecting(let attempt): return attempt > 1 ? "Reconnecting… (\(attempt))" : "Reconnecting…"
        case .lost: return "Connection lost"
        }
    }

    func start() async {
        if !started {
            started = true
        }
        startTimerIfNeeded()
    }

    func tap(_ cell: Cell) {
        guard canTap, game.board[cell] == nil else { return }
        pendingCell = cell
        Task {
            do {
                try await transport.connection.send(.gameUpdate(cell: cell))
            } catch {
                pendingCell = nil
                notice = "Couldn't send your move"
            }
        }
    }

    func restart() {
        guard onlineRole == .host, case .over = phase else { return }
        Task {
            try? await transport.connection.send(.gameReset(boardSize: boardSize, timer: timerSeconds, gameID: gameID))
        }
    }

    func startRematch() {
        guard onlineRole == .host, case .awaitingRematch = phase else { return }
        Task {
            if let gameID {
                try? await transport.api.updatePlayers(gameID: gameID, players: seats)
            }
            try? await transport.connection.send(.gameStart)
        }
    }

    func stop() {
        timerTask?.cancel()
        timerTask = nil
    }

    func leave() {
        timerTask?.cancel()
        reconnectTask?.cancel()
        stallTask?.cancel()
        OnlineSessionRecord.clear()
        let transport = transport
        let code = roomCode
        let isHost = onlineRole == .host
        Task {
            if isHost { try? await transport.matcher.delist(roomCode: code) }
            await transport.connection.close()
        }
    }

    /// Back in the foreground: don't wait for the backoff timer.
    func sceneDidBecomeActive() {
        guard connection != .online, case .playing = phase else { return }
        reconnectTask?.cancel()
        beginReconnect(immediately: true)
    }

    // MARK: Events

    private func handle(_ event: SocketEvent) {
        switch event {
        case .connected:
            break
        case .disconnected:
            beginReconnect(immediately: false)
        case .message(let message):
            handle(message)
        }
    }

    private func handle(_ message: ServerMessage) {
        switch message {
        case .gameUpdate(let snapshot):
            apply(snapshot)
        case .gameState(let snapshot):
            resync(from: snapshot)
        case .gameReset(let payload):
            reset(to: payload)
        case .gameStart:
            phase = .playing
            isGameOverPresented = false
            saveRecord(started: true)
            startTimerIfNeeded()
        case .promotedToPlayer(let seat, _):
            onlineRole = .guest
            mySeat = seat
            notice = "You're in! You play as seat \(seat) next round."
            saveRecord(started: false)
        case .playerJoined(let player):
            if let player, !seats.contains(where: { $0.id == player.id }) { seats.append(player) }
        case .hostAway:
            hostAway = true
        case .hostDisconnected:
            hostAway = false
            phase = .roomClosed("The host ended the room.")
            timerTask?.cancel()
            OnlineSessionRecord.clear()
        case .guestAway(let seat):
            if let seat {
                awaySeats.insert(seat)
                notice = "\(name(of: seat)) lost connection"
                scheduleStallGuard()
            }
        case .guestDisconnected(let seat):
            if let seat { awaySeats.remove(seat) }
        case .playerRejoined(let seat, let who):
            if let seat { awaySeats.remove(seat) }
            if who == .host || seat == 1 { hostAway = false }
            if notice?.hasPrefix("The host lost") == true || notice?.hasSuffix("lost connection") == true { notice = nil }
            stallTask?.cancel()
        case .spectatorCount(let count):
            spectatorCount = count
        case .moveRejected(let reason):
            pendingCell = nil
            switch reason {
            case "not_your_turn": notice = "Not your turn"
            case "occupied": notice = "That tile is already taken"
            default: break
            }
        case .rejoinFailed(let reason):
            phase = .roomClosed(reason == "room_not_found" ? "The room has closed" : "Couldn't rejoin (\(reason))")
            OnlineSessionRecord.clear()
        case .joinError(let message):
            phase = .roomClosed(message)
        case .roomCreated, .playerSlotAssigned, .spectatorAssigned, .unknown:
            break
        }
    }

    /// Apply the echoed move locally when it reproduces the server's state; otherwise rebuild.
    private func apply(_ snapshot: GameSnapshotPayload) {
        timerTask?.cancel()
        timeRemaining = nil
        pendingCell = nil
        let state = snapshot.gameState
        if let players = state.players, !players.isEmpty { seats = players }
        if let gameID = snapshot.gameId { self.gameID = gameID }

        var trial = game
        if let cell = state.moveCell, !game.isOver, game.board[cell] == nil,
           let result = try? trial.place(at: cell), trial.matches(state) {
            game = trial
            spinSequence += 1
            for (tile, event) in SpinSchedule.events(for: result, sequence: spinSequence, continuousIndex: true) {
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
            shapeLog += result.newShapes
        } else if let rebuilt = Game(restoring: snapshot, timerSeconds: timerSeconds) {
            game = rebuilt
            shapeLog = state.allShapes
            lastMove = nil
            // The owner change flips the tile; nothing to spin on a resync.
            if state.moveCell != nil { placeCount += 1 }
            #if DEBUG
            notice = "Resynced with the server"
            #endif
        }
        spectatorCount = snapshot.spectatorCount ?? spectatorCount

        if game.isOver {
            finish()
        } else {
            phase = .playing
            startTimerIfNeeded()
            scheduleStallGuard()
        }
    }

    private func resync(from snapshot: GameSnapshotPayload) {
        guard let rebuilt = Game(restoring: snapshot, timerSeconds: timerSeconds) else { return }
        game = rebuilt
        boardSize = rebuilt.board.size
        seats = snapshot.seats
        shapeLog = snapshot.gameState.allShapes
        spectatorCount = snapshot.spectatorCount ?? spectatorCount
        if let gameID = snapshot.gameId { self.gameID = gameID }
        pendingCell = nil
        lastMove = nil
        if game.isOver {
            phase = .over
        } else if snapshot.gameState.looksInProgress || (OnlineSessionRecord.load()?.started ?? false) {
            phase = .playing
            startTimerIfNeeded()
        } else {
            phase = .awaitingRematch(hostReady: onlineRole == .host)
        }
    }

    private func reset(to reset: GameResetPayload) {
        timerTask?.cancel()
        stallTask?.cancel()
        seats = reset.players
        boardSize = reset.boardSize
        let snapshot = GameSnapshotPayload(gameState: .empty(boardSize: reset.boardSize, players: reset.players), timer: reset.timer, boardSize: reset.boardSize)
        if let fresh = Game(restoring: snapshot, timerSeconds: timerSeconds) { game = fresh }
        shapeLog = []
        spins = [:]
        lastMove = nil
        pendingCell = nil
        timeRemaining = nil
        turnDeadline = nil
        isGameOverPresented = false
        endPosted = false
        awaySeats = []
        spectatorCount = reset.spectatorCount ?? 0
        phase = .awaitingRematch(hostReady: onlineRole == .host)
        saveRecord(started: false)
    }

    private func finish() {
        phase = .over
        timerTask?.cancel()
        stallTask?.cancel()
        if onlineRole == .host, !endPosted, let gameID {
            endPosted = true
            let winner = game.isDraw ? "" : (playerID(of: game.standings[0].id) ?? "")
            let scores = game.players.map { ScoreEntry(playerId: playerID(of: $0.id) ?? String($0.id), score: $0.score) }
            let api = transport.api
            Task { try? await api.endGame(GameEndRequest(gameId: gameID, winnerId: winner, scores: scores)) }
        }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if case .over = phase { isGameOverPresented = true }
        }
    }

    // MARK: Reconnect

    private func beginReconnect(immediately: Bool) {
        guard case .playing = phase else { return }
        reconnectTask?.cancel()
        connection = .reconnecting(attempt: 1)
        timerTask?.cancel()
        let window: Duration = .seconds(onlineRole == .host ? 60 : 30)
        let code = roomCode
        let seat = mySeat ?? 0
        let role = onlineRole
        reconnectTask = Task {
            if immediately {
                if (try? await transport.connection.connect()) != nil,
                   (try? await transport.connection.send(.rejoinRoom(roomCode: code, playerID: seat, role: role))) != nil {
                    connection = .online
                    return
                }
            }
            let ok = await transport.connection.reconnect(until: .now + window, onAttempt: { [weak self] attempt in
                self?.connection = .reconnecting(attempt: attempt)
            }, afterConnect: { [transport] in
                try await transport.connection.send(.rejoinRoom(roomCode: code, playerID: seat, role: role))
            })
            guard !Task.isCancelled else { return }
            if ok {
                connection = .online
            } else {
                connection = .lost
                notice = "You were disconnected from the room"
            }
        }
    }

    // MARK: Timer and stall guard

    private func startTimerIfNeeded() {
        timerTask?.cancel()
        turnDeadline = nil
        guard timerSeconds > 0, case .playing = phase, !game.isOver else { return }
        timeRemaining = timerSeconds
        turnDeadline = .now + TimeInterval(timerSeconds)
        timerTask = Task {
            while let remaining = timeRemaining, remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                timeRemaining = remaining - 1
            }
            guard !Task.isCancelled else { return }
            timerExpired()
        }
    }

    private func timerExpired() {
        guard case .playing = phase, !game.isOver, game.currentPlayer.id == mySeat, onlineRole != .spectator else { return }
        Task { try? await transport.connection.send(.turnComplete) }
    }

    /// Host only: an absent player's turn is skipped after the timer (or 30 s) so the match
    /// can go on; the server plays a random tile for them.
    private func scheduleStallGuard() {
        stallTask?.cancel()
        guard onlineRole == .host, case .playing = phase, !game.isOver, awaySeats.contains(game.currentPlayer.id) else { return }
        let seat = game.currentPlayer.id
        stallTask = Task {
            try? await Task.sleep(for: .seconds(max(timerSeconds, 30)))
            guard !Task.isCancelled, case .playing = phase, game.currentPlayer.id == seat, awaySeats.contains(seat) else { return }
            try? await transport.connection.send(.turnComplete)
            notice = "Skipped \(name(of: seat))'s turn"
        }
    }

    // MARK: Helpers

    /// The underlying socket (tests simulate drops on it).
    var debugSocket: any GameSocket { transport.connection.socket }

    private func name(of seat: Int) -> String {
        game.players.first { $0.id == seat }?.name ?? seats.first { $0.id == seat }?.displayName ?? "Player \(seat)"
    }

    private func playerID(of seat: Int) -> String? {
        seats.first { $0.id == seat }?.playerId ?? (seat == mySeat ? me.playerID : nil)
    }

    private func saveRecord(started: Bool) {
        OnlineSessionRecord(roomCode: roomCode, seat: mySeat, role: onlineRole, gameID: gameID, boardSize: boardSize,
                            timerSeconds: timerSeconds, started: started, savedAt: Date(), backendID: transport.backendID).save()
    }
}
