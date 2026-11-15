import Foundation
import SquareOffCore

/// In-process stand-in for `server/src/routes/websocket.py`: rooms by code, slot and colour
/// assignment, authoritative scoring with the rules engine, spectators, grace periods and
/// rematches, with the same message vocabulary. It implements the *fixed* semantics the iOS
/// server branch adds (turn ownership, no turn advance on a bad move, seats kept during a match).
///
/// Bots make it playable alone: a room that waits too long gets a bot opponent, and bot-hosted
/// rooms (seeded for the lobby and quick match) start the game when a human joins.
public actor MockRoomServer {
    public typealias ConnectionID = Int

    public struct Configuration: Sendable {
        public var hostGrace: Duration = .seconds(60)
        public var guestGrace: Duration = .seconds(30)
        /// Delay before a bot joins a human-hosted room that is still alone; nil disables bots.
        public var botJoinDelay: Duration? = .seconds(2)
        public var botThinkMillis: ClosedRange<Int> = 500...1500
        /// Delay before a bot host starts (or restarts) the game once a human is seated.
        public var botHostStartDelay: Duration = .seconds(1)
        public var botLevels: [CPULevel] = [.maxMin, .maxMinOptimal, .maxRandom]
        public var defaultColors: [String] = PlayerPayload.defaultColors

        public init() {}

        /// No delays, no automatic bots: for deterministic tests.
        public static var instant: Configuration {
            var c = Configuration()
            c.hostGrace = .zero
            c.guestGrace = .zero
            c.botJoinDelay = nil
            c.botThinkMillis = 0...0
            c.botHostStartDelay = .zero
            return c
        }
    }

    public enum Role: Sendable { case host, guest, spectator }

    struct Connection {
        let id: ConnectionID
        let continuation: AsyncStream<ServerMessage>.Continuation
        var roomCode: Int?
        var seat: Int?
        var role: Role?
    }

    struct Room {
        let code: Int
        var host: ConnectionID?
        var guests: [ConnectionID] = []
        var spectators: [ConnectionID] = []
        var seats: [PlayerPayload]
        var matchInProgress = false
        var timer: Int
        var boardSize: Int
        var gameID: Int?
        var game: Game?
        var disconnectedGuests: Set<Int> = []
        var hostGraceTask: Task<Void, Never>?
        var guestGraceTasks: [Int: Task<Void, Never>] = [:]
        var bots: [Int: CPUStrategy] = [:]
        var botHost: Bool = false
        var botTask: Task<Void, Never>?
        var lastTurnComplete: ContinuousClock.Instant?
        var listed = false
        var hostLabel = "Player 1"
        var hostKey = ""
        let createdAt = Date()
        var lastHeartbeat = Date()

        var hostPresent: Bool { host != nil || botHost }
        var spectatorCount: Int { spectators.count }
    }

    private let configuration: Configuration
    private var connections: [ConnectionID: Connection] = [:]
    private var rooms: [Int: Room] = [:]
    private var nextConnectionID = 1
    private var rng = SystemRandomNumberGenerator()

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    // MARK: Transport side

    public func connect() -> (ConnectionID, AsyncStream<ServerMessage>) {
        let id = nextConnectionID
        nextConnectionID += 1
        let (stream, continuation) = AsyncStream<ServerMessage>.makeStream()
        connections[id] = Connection(id: id, continuation: continuation)
        return (id, stream)
    }

    public func disconnect(_ id: ConnectionID) {
        guard let connection = connections.removeValue(forKey: id) else { return }
        connection.continuation.finish()
        guard let code = connection.roomCode, var room = rooms[code] else { return }
        switch connection.role {
        case .host:
            room.host = nil
            room.listed = false
            rooms[code] = room
            broadcast(code, .hostAway, excluding: id)
            rooms[code]?.hostGraceTask?.cancel()
            rooms[code]?.hostGraceTask = Task { [grace = configuration.hostGrace] in
                try? await Task.sleep(for: grace)
                guard !Task.isCancelled else { return }
                self.expireHost(code)
            }
        case .guest:
            room.guests.removeAll { $0 == id }
            if let seat = connection.seat {
                room.disconnectedGuests.insert(seat)
                rooms[code] = room
                broadcast(code, .guestAway(playerId: seat))
                rooms[code]?.guestGraceTasks[seat]?.cancel()
                rooms[code]?.guestGraceTasks[seat] = Task { [grace = configuration.guestGrace] in
                    try? await Task.sleep(for: grace)
                    guard !Task.isCancelled else { return }
                    self.expireGuest(code, seat: seat)
                }
            } else {
                rooms[code] = room
            }
        case .spectator:
            room.spectators.removeAll { $0 == id }
            rooms[code] = room
            broadcast(code, .spectatorCount(room.spectatorCount))
        case nil:
            break
        }
    }

    public func handle(_ message: ClientMessage, from id: ConnectionID) {
        guard connections[id] != nil else { return }
        switch message {
        case let .createRoom(player, boardSize, timer, gameID, roomCode):
            createRoom(from: id, player: player, boardSize: boardSize, timer: timer, gameID: gameID, preferred: roomCode)
        case let .requestPlayerSlot(code):
            requestSlot(from: id, code: code)
        case let .joinRoom(code, player):
            join(from: id, code: code, player: player)
        case let .joinAsSpectator(code):
            joinAsSpectator(from: id, code: code)
        case let .rejoinRoom(code, playerID, role):
            rejoin(from: id, code: code, playerID: playerID, role: role)
        case .gameStart:
            if let code = connections[id]?.roomCode { startGame(code) }
        case let .gameUpdate(cell):
            gameUpdate(from: id, cell: cell)
        case .turnComplete:
            turnComplete(from: id)
        case let .gameReset(boardSize, timer, gameID):
            if let code = connections[id]?.roomCode { reset(code, boardSize: boardSize, timer: timer, gameID: gameID) }
        }
    }

    // MARK: Seeding and matcher support

    /// A listed room hosted by a bot; the game starts shortly after a human joins.
    public func seedBotRoom(code: Int, boardSize: Int, timer: Int, listed: Bool = true, hostLevel: CPULevel = .maxMin) {
        guard rooms[code] == nil else { return }
        let strategy = CPUStrategy(level: hostLevel.offlineFallback) ?? .maxMin
        let seat = PlayerPayload.seat(id: 1, name: "Bot · L\(hostLevel.number)", colorHex: configuration.defaultColors[0],
                                      playerID: "bot-\(hostLevel.rawValue)", isCPU: true, cpuType: hostLevel.cpuType)
        var room = Room(code: code, host: nil, seats: [seat], timer: timer, boardSize: boardSize)
        room.botHost = true
        room.bots[1] = strategy
        room.listed = listed
        room.hostLabel = seat.displayName
        room.hostKey = seat.playerId ?? "bot"
        rooms[code] = room
    }

    /// Two bots mid-game, for spectating. `moves` are played instantly; the rest play out live.
    public func seedBotMatchInProgress(code: Int, boardSize: Int, moves: Int, levels: (CPULevel, CPULevel) = (.maxMinOptimal, .maxMin)) {
        guard rooms[code] == nil else { return }
        let seats = [
            PlayerPayload.seat(id: 1, name: "Bot · L\(levels.0.number)", colorHex: configuration.defaultColors[0],
                               playerID: "bot-1", isCPU: true, cpuType: levels.0.cpuType),
            PlayerPayload.seat(id: 2, name: "Bot · L\(levels.1.number)", colorHex: configuration.defaultColors[1],
                               playerID: "bot-2", isCPU: true, cpuType: levels.1.cpuType),
        ]
        var room = Room(code: code, host: nil, seats: seats, timer: 0, boardSize: boardSize)
        room.botHost = true
        room.bots = [1: CPUStrategy(level: levels.0.offlineFallback) ?? .maxMin,
                     2: CPUStrategy(level: levels.1.offlineFallback) ?? .maxMin]
        room.matchInProgress = true
        room.game = makeGame(for: room)
        var played = 0
        while played < moves, var game = room.game, !game.isOver {
            let strategy = room.bots[game.currentPlayer.id] ?? .random
            _ = try? game.place(at: strategy.chooseMove(in: game))
            room.game = game
            played += 1
        }
        rooms[code] = room
        scheduleBotTurn(code)
    }

    public func roomExists(_ code: Int) -> Bool { rooms[code] != nil }

    public func newRoomCode() -> Int {
        while true {
            let code = Int.random(in: 10_000...99_999, using: &rng)
            if rooms[code] == nil { return code }
        }
    }

    public func listedRooms(boardSize: Int?, timer: Int?) -> [OpenRoomDTO] {
        rooms.values
            .filter { $0.listed && !$0.matchInProgress && $0.hostPresent }
            .filter { boardSize == nil || $0.boardSize == boardSize }
            .filter { timer == nil || $0.timer == timer }
            .sorted { $0.createdAt < $1.createdAt }
            .map { room in
                OpenRoomDTO(roomCode: room.code, boardSize: room.boardSize, timer: room.timer,
                            slotsFilled: room.seats.count, listed: room.listed, hostLabel: room.hostLabel,
                            hostKey: room.hostKey, createdAt: room.createdAt.timeIntervalSince1970,
                            lastHeartbeat: room.lastHeartbeat.timeIntervalSince1970, gameId: room.gameID)
            }
    }

    public func upsertListing(code: Int, listed: Bool, hostLabel: String, hostKey: String) -> AdvertiseRoomResponse? {
        guard var room = rooms[code] else { return nil }
        room.listed = listed && !room.matchInProgress
        room.hostLabel = hostLabel
        room.hostKey = hostKey
        room.lastHeartbeat = Date()
        rooms[code] = room
        return AdvertiseRoomResponse(roomCode: code, listed: room.listed, slotsFilled: room.seats.count)
    }

    public func delist(code: Int) {
        rooms[code]?.listed = false
    }

    /// A listed bot room matching the request, created on demand (quick match).
    public func botRoom(boardSize: Int, timer: Int) -> Int {
        if let room = rooms.values.first(where: { $0.botHost && $0.listed && !$0.matchInProgress && $0.seats.count < 4 && $0.boardSize == boardSize && $0.timer == timer }) {
            return room.code
        }
        let code = newRoomCode()
        seedBotRoom(code: code, boardSize: boardSize, timer: timer, listed: true,
                    hostLevel: configuration.botLevels.randomElement(using: &rng) ?? .maxMin)
        return code
    }

    // MARK: Handlers

    private func createRoom(from id: ConnectionID, player: PlayerPayload, boardSize: Int, timer: Int, gameID: Int?, preferred: Int?) {
        let code = preferred.flatMap { rooms[$0] == nil ? $0 : nil } ?? newRoomCode()
        var room = Room(code: code, host: id, seats: [player], timer: timer, boardSize: boardSize)
        room.gameID = gameID
        room.hostLabel = player.displayName
        room.hostKey = player.playerId ?? "host"
        rooms[code] = room
        connections[id]?.roomCode = code
        connections[id]?.seat = player.id
        connections[id]?.role = .host
        send(id, .roomCreated(RoomCreatedPayload(roomCode: code, timer: timer, boardSize: boardSize, currentPlayerIndex: 0, gameId: gameID)))
        scheduleBotJoin(code)
    }

    private func requestSlot(from id: ConnectionID, code: Int) {
        guard let room = rooms[code], room.hostPresent || room.host == nil && !room.seats.isEmpty else {
            send(id, .joinError(message: "Room not found"))
            return
        }
        if room.matchInProgress || room.seats.count >= 4 {
            send(id, .spectatorAssigned)
            return
        }
        let (slot, color) = nextSlot(in: room)
        send(id, .playerSlotAssigned(id: slot, color: color))
    }

    private func nextSlot(in room: Room) -> (Int, String) {
        let usedIDs = Set(room.seats.map(\.id))
        let usedColors = Set(room.seats.compactMap(\.fillStyle))
        let slot = [2, 3, 4].first { !usedIDs.contains($0) } ?? 4
        let color = configuration.defaultColors.dropFirst().first { !usedColors.contains($0) } ?? configuration.defaultColors[(slot - 1) % 4]
        return (slot, color)
    }

    private func join(from id: ConnectionID, code: Int, player: PlayerPayload) {
        guard var room = rooms[code] else {
            send(id, .joinError(message: "Room full or not found"))
            return
        }
        if let index = room.seats.firstIndex(where: { $0.id == player.id }) {
            // Idempotent re-send (promoted spectator): refresh the seat, don't duplicate it.
            var merged = room.seats[index]
            merged.name = player.name ?? merged.name
            merged.fillStyle = player.fillStyle ?? merged.fillStyle
            merged.playerId = player.playerId ?? merged.playerId
            room.seats[index] = merged
            if !room.guests.contains(id) { room.guests.append(id) }
            room.game = room.matchInProgress ? room.game : makeGame(for: room)
            rooms[code] = room
            attach(id, to: code, seat: player.id, role: .guest)
            broadcast(code, .gameState(snapshot(room)))
            return
        }
        guard room.seats.count < 4 else {
            send(id, .joinError(message: "Room full or not found"))
            return
        }
        var seat = player
        seat.isCPU = seat.isCPU ?? false
        room.seats.append(seat)
        room.guests.append(id)
        room.game = makeGame(for: room)
        room.lastHeartbeat = Date()
        rooms[code] = room
        attach(id, to: code, seat: seat.id, role: .guest)
        broadcast(code, .playerJoined(seat))
        broadcast(code, .gameState(snapshot(rooms[code]!)))
        scheduleBotHostStart(code)
    }

    private func joinAsSpectator(from id: ConnectionID, code: Int) {
        guard var room = rooms[code] else {
            send(id, .joinError(message: "Room not found"))
            return
        }
        room.spectators.append(id)
        rooms[code] = room
        attach(id, to: code, seat: nil, role: .spectator)
        send(id, .gameState(snapshot(room)))
        broadcast(code, .spectatorCount(room.spectatorCount))
    }

    private func rejoin(from id: ConnectionID, code: Int, playerID: Int, role: OnlineRole) {
        guard var room = rooms[code] else {
            send(id, .rejoinFailed(reason: "room_not_found"))
            return
        }
        if role == .spectator {
            joinAsSpectator(from: id, code: code)
            return
        }
        guard room.seats.contains(where: { $0.id == playerID }) else {
            send(id, .rejoinFailed(reason: "player_not_found"))
            return
        }
        if role == .host {
            guard room.host == nil else {
                send(id, .rejoinFailed(reason: "slot_in_use"))
                return
            }
            room.host = id
            room.hostGraceTask?.cancel()
            room.hostGraceTask = nil
            rooms[code] = room
            attach(id, to: code, seat: playerID, role: .host)
        } else {
            guard !room.guests.contains(where: { connections[$0]?.seat == playerID }) else {
                send(id, .rejoinFailed(reason: "slot_in_use"))
                return
            }
            room.guests.append(id)
            room.disconnectedGuests.remove(playerID)
            room.guestGraceTasks[playerID]?.cancel()
            room.guestGraceTasks[playerID] = nil
            rooms[code] = room
            attach(id, to: code, seat: playerID, role: .guest)
        }
        send(id, .gameState(snapshot(rooms[code]!)))
        broadcast(code, .playerRejoined(playerId: playerID, role: role))
    }

    private func startGame(_ code: Int) {
        guard var room = rooms[code] else { return }
        room.matchInProgress = true
        room.listed = false
        if room.game == nil { room.game = makeGame(for: room) }
        rooms[code] = room
        broadcast(code, .gameStart(spectatorCount: room.spectatorCount))
        scheduleBotTurn(code)
    }

    private func gameUpdate(from id: ConnectionID, cell: Cell) {
        guard let connection = connections[id], let code = connection.roomCode, let room = rooms[code] else { return }
        guard connection.role != .spectator, let game = room.game else { return }
        guard connection.seat == game.currentPlayer.id else {
            send(id, .moveRejected(reason: "not_your_turn"))
            return
        }
        guard !game.isOver else {
            send(id, .moveRejected(reason: "game_over"))
            return
        }
        guard (0..<game.board.size).contains(cell.row), (0..<game.board.size).contains(cell.col), game.board[cell] == nil else {
            send(id, .moveRejected(reason: "occupied"))
            return
        }
        play(code, cell: cell)
    }

    private func turnComplete(from id: ConnectionID) {
        guard let connection = connections[id], let code = connection.roomCode, var room = rooms[code] else { return }
        guard connection.role != .spectator, let game = room.game, !game.isOver else { return }
        let now = ContinuousClock.now
        if let last = room.lastTurnComplete, now - last < .milliseconds(80) { return }
        room.lastTurnComplete = now
        rooms[code] = room
        guard let cell = game.board.emptyCells.randomElement(using: &rng) else { return }
        play(code, cell: cell)
    }

    /// Applies a legal move for the current player and broadcasts the `GAME_UPDATE` echo.
    private func play(_ code: Int, cell: Cell) {
        guard var room = rooms[code], var game = room.game else { return }
        guard let move = try? game.place(at: cell) else { return }
        room.game = game
        rooms[code] = room
        broadcast(code, .gameUpdate(snapshot(room, move: move)))
        scheduleBotTurn(code)
    }

    private func reset(_ code: Int, boardSize: Int, timer: Int, gameID: Int?) {
        guard var room = rooms[code] else { return }
        room.matchInProgress = false
        room.boardSize = boardSize
        room.timer = timer
        if let gameID { room.gameID = gameID }
        for index in room.seats.indices {
            room.seats[index].currentScore = 0
            room.seats[index].currentMultiplier = 1
            room.seats[index].scoreHistory = []
        }
        var promoted: [(ConnectionID, Int, String)] = []
        while !room.spectators.isEmpty, room.seats.count < 4 {
            let spectator = room.spectators.removeFirst()
            let (slot, color) = nextSlot(in: room)
            room.seats.append(PlayerPayload.seat(id: slot, name: "Player \(slot)", colorHex: color, playerID: nil))
            room.guests.append(spectator)
            connections[spectator]?.seat = slot
            connections[spectator]?.role = .guest
            promoted.append((spectator, slot, color))
        }
        room.botTask?.cancel()
        room.botTask = nil
        room.game = makeGame(for: room)
        rooms[code] = room
        for (id, slot, color) in promoted {
            send(id, .promotedToPlayer(id: slot, color: color))
        }
        broadcast(code, .gameReset(GameResetPayload(boardSize: boardSize, timer: timer, players: room.seats, spectatorCount: room.spectatorCount)))
        scheduleBotHostStart(code)
    }

    // MARK: Grace periods

    private func expireHost(_ code: Int) {
        guard let room = rooms[code], room.host == nil, !room.botHost else { return }
        rooms[code] = nil
        for id in room.guests + room.spectators {
            send(id, .hostDisconnected)
            connections[id]?.roomCode = nil
        }
    }

    private func expireGuest(_ code: Int, seat: Int) {
        guard var room = rooms[code], room.disconnectedGuests.contains(seat) else { return }
        room.disconnectedGuests.remove(seat)
        room.guestGraceTasks[seat] = nil
        if !room.matchInProgress {
            room.seats.removeAll { $0.id == seat }
            room.game = makeGame(for: room)
        }
        rooms[code] = room
        if !room.matchInProgress {
            broadcast(code, .gameState(snapshot(room)))
        }
    }

    // MARK: Bots

    private func scheduleBotJoin(_ code: Int) {
        guard let delay = configuration.botJoinDelay else { return }
        Task {
            try? await Task.sleep(for: delay)
            self.botJoin(code)
        }
    }

    private func botJoin(_ code: Int) {
        guard var room = rooms[code], room.seats.count < 2, !room.matchInProgress, room.hostPresent else { return }
        let level = configuration.botLevels.randomElement(using: &rng) ?? .maxMin
        let (slot, color) = nextSlot(in: room)
        let seat = PlayerPayload.seat(id: slot, name: "Bot · L\(level.number)", colorHex: color,
                                      playerID: "bot-\(level.rawValue)", isCPU: true, cpuType: level.cpuType)
        room.seats.append(seat)
        room.bots[slot] = CPUStrategy(level: level.offlineFallback) ?? .maxMin
        room.game = makeGame(for: room)
        rooms[code] = room
        broadcast(code, .playerJoined(seat))
        broadcast(code, .gameState(snapshot(room)))
    }

    private func scheduleBotHostStart(_ code: Int) {
        guard let room = rooms[code], room.botHost, !room.matchInProgress, room.seats.count >= 2 else { return }
        Task { [delay = configuration.botHostStartDelay] in
            try? await Task.sleep(for: delay)
            guard let room = self.rooms[code], room.botHost, !room.matchInProgress, room.seats.count >= 2 else { return }
            self.startGame(code)
        }
    }

    private func scheduleBotTurn(_ code: Int) {
        guard var room = rooms[code] else { return }
        room.botTask?.cancel()
        room.botTask = nil
        guard room.matchInProgress, let game = room.game, !game.isOver, room.bots[game.currentPlayer.id] != nil else {
            rooms[code] = room
            return
        }
        let delay = Int.random(in: configuration.botThinkMillis, using: &rng)
        let expectedMover = game.currentPlayer.id
        room.botTask = Task {
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled else { return }
            self.botMove(code, expecting: expectedMover)
        }
        rooms[code] = room
    }

    private func botMove(_ code: Int, expecting mover: Int) {
        guard let room = rooms[code], room.matchInProgress, let game = room.game, !game.isOver,
              game.currentPlayer.id == mover, let strategy = room.bots[mover] else { return }
        play(code, cell: strategy.chooseMove(in: game))
    }

    // MARK: Helpers

    private func makeGame(for room: Room) -> Game? {
        let seats = room.seats.map { PlayerPayload.seat(id: $0.id, name: $0.displayName, colorHex: $0.colorHex, playerID: $0.playerId, isCPU: $0.isCPU ?? false, cpuType: $0.cpuType) }
        return Game(restoring: GameSnapshotPayload(gameState: .empty(boardSize: room.boardSize, players: seats)), timerSeconds: room.timer)
    }

    private func snapshot(_ room: Room, move: MoveResult? = nil) -> GameSnapshotPayload {
        let state: GameStatePayload
        if let game = room.game {
            state = GameStatePayload(game: game, seats: room.seats, move: move)
        } else {
            state = .empty(boardSize: room.boardSize, players: room.seats)
        }
        return GameSnapshotPayload(gameState: state, players: state.players, timer: room.timer, boardSize: room.boardSize,
                                   currentPlayerIndex: state.currentPlayerIndex, gameId: room.gameID, spectatorCount: room.spectatorCount)
    }

    private func attach(_ id: ConnectionID, to code: Int, seat: Int?, role: Role) {
        connections[id]?.roomCode = code
        connections[id]?.seat = seat
        connections[id]?.role = role
    }

    private func send(_ id: ConnectionID, _ message: ServerMessage) {
        connections[id]?.continuation.yield(message)
    }

    private func broadcast(_ code: Int, _ message: ServerMessage, excluding: ConnectionID? = nil) {
        guard let room = rooms[code] else { return }
        var recipients: [ConnectionID] = []
        if let host = room.host { recipients.append(host) }
        recipients += room.guests + room.spectators
        for id in recipients where id != excluding {
            send(id, message)
        }
    }
}
