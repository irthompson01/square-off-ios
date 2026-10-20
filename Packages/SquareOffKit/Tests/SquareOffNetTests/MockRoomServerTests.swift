import Foundation
import Testing
import SquareOffCore
@testable import SquareOffNet

/// Pulls events off a socket's stream one at a time, with a timeout so a missing message fails
/// instead of hanging the suite.
final class EventReader {
    private var iterator: AsyncStream<SocketEvent>.AsyncIterator

    init(_ socket: any GameSocket) async {
        iterator = await socket.events.makeAsyncIterator()
    }

    func next() async -> SocketEvent? {
        await iterator.next()
    }

    /// The next server message whose type name matches, skipping everything else.
    func message(_ typeName: String, within: Duration = .seconds(2)) async throws -> ServerMessage {
        let deadline = ContinuousClock.now + within
        while ContinuousClock.now < deadline {
            guard let event = await next() else { break }
            if case let .message(message) = event, message.typeName == typeName { return message }
        }
        throw TimeoutError(typeName)
    }

    struct TimeoutError: Error { let typeName: String; init(_ t: String) { typeName = t } }
}

private func seat(_ id: Int, _ name: String) -> PlayerPayload {
    PlayerPayload.seat(id: id, name: name, colorHex: PlayerPayload.defaultColors[id - 1], playerID: "user-\(id)")
}

/// Host and guest connected to a fresh room, game not yet started.
private func hostedRoom(_ server: MockRoomServer, boardSize: Int = 6) async throws -> (host: MockGameSocket, hostEvents: EventReader, guest: MockGameSocket, guestEvents: EventReader, code: Int) {
    let host = MockGameSocket(server: server)
    let hostEvents = await EventReader(host)
    await host.connect()
    try await host.send(.createRoom(player: seat(1, "Host"), boardSize: boardSize, timer: 0, gameID: 9, roomCode: nil))
    guard case let .roomCreated(created) = try await hostEvents.message("ROOM_CREATED") else { throw EventReader.TimeoutError("ROOM_CREATED") }

    let guest = MockGameSocket(server: server)
    let guestEvents = await EventReader(guest)
    await guest.connect()
    try await guest.send(.requestPlayerSlot(roomCode: created.roomCode))
    guard case let .playerSlotAssigned(slot, color) = try await guestEvents.message("PLAYER_SLOT_ASSIGNED") else { throw EventReader.TimeoutError("SLOT") }
    #expect(slot == 2 && color == PlayerPayload.defaultColors[1])
    try await guest.send(.joinRoom(roomCode: created.roomCode, player: seat(2, "Guest")))
    _ = try await hostEvents.message("GAME_STATE")
    _ = try await guestEvents.message("GAME_STATE")
    return (host, hostEvents, guest, guestEvents, created.roomCode)
}

@Suite("Mock room server")
struct MockRoomServerTests {
    @Test func hostAndGuestPlayAFullGameTheRulesEngineAgreesWith() async throws {
        let server = MockRoomServer(configuration: .instant)
        let room = try await hostedRoom(server)
        try await room.host.send(.gameStart)
        _ = try await room.hostEvents.message("GAME_START")
        _ = try await room.guestEvents.message("GAME_START")

        var local = Game(boardSize: 6, players: [
            PlayerState(id: 1, name: "Host", colorHex: "#0583D2"),
            PlayerState(id: 2, name: "Guest", colorHex: "#FF3131"),
        ])
        while !local.isOver {
            let mover = local.currentPlayer.id
            let cell = CPUStrategy.maxMinOptimal.chooseMove(in: local)
            try await (mover == 1 ? room.host : room.guest).send(.gameUpdate(cell: cell))
            guard case let .gameUpdate(update) = try await room.hostEvents.message("GAME_UPDATE") else { Issue.record("no echo"); return }
            _ = try await room.guestEvents.message("GAME_UPDATE")
            try local.place(at: cell)
            #expect(update.gameState.moveCell == cell)
            #expect(local.matches(update.gameState))
        }
    }

    @Test func badMovesAreRejectedWithoutAdvancingTheTurn() async throws {
        let server = MockRoomServer(configuration: .instant)
        let room = try await hostedRoom(server)
        try await room.host.send(.gameStart)
        _ = try await room.guestEvents.message("GAME_START")

        try await room.guest.send(.gameUpdate(cell: Cell(row: 0, col: 0)))
        #expect(try await room.guestEvents.message("MOVE_REJECTED") == .moveRejected(reason: "not_your_turn"))

        try await room.host.send(.gameUpdate(cell: Cell(row: 0, col: 0)))
        _ = try await room.guestEvents.message("GAME_UPDATE")
        _ = try await room.hostEvents.message("GAME_UPDATE")
        try await room.guest.send(.gameUpdate(cell: Cell(row: 0, col: 0)))
        #expect(try await room.guestEvents.message("MOVE_REJECTED") == .moveRejected(reason: "occupied"))

        try await room.guest.send(.turnComplete)   // timer expiry plays a random legal cell for the guest
        guard case let .gameUpdate(update) = try await room.hostEvents.message("GAME_UPDATE") else { Issue.record("no update"); return }
        #expect(update.gameState.currentPlayerIndex == 0)
        #expect(update.gameState.boardState[try #require(update.gameState.rowIndex)][try #require(update.gameState.colIndex)]?.id == 2)
    }

    @Test func dropAndRejoinRestoresTheSnapshot() async throws {
        let server = MockRoomServer(configuration: .instant)
        let room = try await hostedRoom(server)
        try await room.host.send(.gameStart)
        _ = try await room.guestEvents.message("GAME_START")
        try await room.host.send(.gameUpdate(cell: Cell(row: 2, col: 2)))
        guard case let .gameUpdate(before) = try await room.guestEvents.message("GAME_UPDATE") else { Issue.record("no update"); return }

        await room.guest.simulateDrop()
        #expect(try await room.hostEvents.message("GUEST_AWAY") == .guestAway(playerId: 2))

        await room.guest.connect()
        try await room.guest.send(.rejoinRoom(roomCode: room.code, playerID: 2, role: .guest))
        guard case let .gameState(after) = try await room.guestEvents.message("GAME_STATE") else { Issue.record("no state"); return }
        #expect(after.gameState.boardState == before.gameState.boardState)
        #expect(after.seats.map(\.id) == [1, 2])
        #expect(try await room.hostEvents.message("PLAYER_REJOINED") == .playerRejoined(playerId: 2, role: .guest))

        // Still the guest's turn and the seat survived the (zero-length) grace period.
        try await room.guest.send(.gameUpdate(cell: Cell(row: 3, col: 3)))
        _ = try await room.hostEvents.message("GAME_UPDATE")
    }

    @Test func lateJoinerSpectatesAndIsPromotedOnReset() async throws {
        let server = MockRoomServer(configuration: .instant)
        let room = try await hostedRoom(server)
        try await room.host.send(.gameStart)
        _ = try await room.guestEvents.message("GAME_START")

        let spectator = MockGameSocket(server: server)
        let spectatorEvents = await EventReader(spectator)
        await spectator.connect()
        try await spectator.send(.requestPlayerSlot(roomCode: room.code))
        #expect(try await spectatorEvents.message("SPECTATOR_ASSIGNED") == .spectatorAssigned)
        try await spectator.send(.joinAsSpectator(roomCode: room.code))
        guard case let .gameState(state) = try await spectatorEvents.message("GAME_STATE") else { Issue.record("no state"); return }
        #expect(state.spectatorCount == 1)
        #expect(try await room.hostEvents.message("SPECTATOR_COUNT") == .spectatorCount(1))

        try await room.host.send(.gameReset(boardSize: 6, timer: 0, gameID: nil))
        #expect(try await spectatorEvents.message("PROMOTED_TO_PLAYER") == .promotedToPlayer(id: 3, color: PlayerPayload.defaultColors[2]))
        guard case let .gameReset(reset) = try await room.hostEvents.message("GAME_RESET") else { Issue.record("no reset"); return }
        #expect(reset.players.map(\.id) == [1, 2, 3])
        #expect(reset.spectatorCount == 0)
    }

    @Test func aBotJoinsALonelyRoomAndPlaysToTheEnd() async throws {
        var configuration = MockRoomServer.Configuration.instant
        configuration.botJoinDelay = .zero
        let server = MockRoomServer(configuration: configuration)
        let host = MockGameSocket(server: server)
        let events = await EventReader(host)
        await host.connect()
        try await host.send(.createRoom(player: seat(1, "Host"), boardSize: 6, timer: 0, gameID: nil, roomCode: 4242))
        _ = try await events.message("ROOM_CREATED")
        guard case let .playerJoined(bot) = try await events.message("PLAYER_JOINED") else { Issue.record("no bot"); return }
        #expect(bot?.isCPU == true)
        #expect(bot?.name?.hasPrefix("Bot") == true)
        _ = try await events.message("GAME_STATE")

        try await host.send(.gameStart)
        _ = try await events.message("GAME_START")
        var local = Game(boardSize: 6, players: [
            PlayerState(id: 1, name: "Host", colorHex: "#0583D2"),
            PlayerState(id: 2, name: "Bot", colorHex: "#FF3131", isCPU: true),
        ])
        while !local.isOver {
            if local.currentPlayer.id == 1 {
                try await host.send(.gameUpdate(cell: CPUStrategy.maxMin.chooseMove(in: local)))
            }
            guard case let .gameUpdate(update) = try await events.message("GAME_UPDATE") else { Issue.record("no update"); return }
            try local.place(at: try #require(update.gameState.moveCell))
            #expect(local.matches(update.gameState))
        }
        #expect(local.isOver)
    }

    @Test func quickMatchResolvesToAListedBotRoom() async throws {
        let server = MockRoomServer(configuration: .instant)
        let matcher = MockMatcherAPI(server: server, ticketDelay: .zero)
        let rooms = try await matcher.openRooms(boardSize: nil, timer: nil, limit: 10, offset: 0)
        #expect(rooms.count == 3)
        let ticket = try await matcher.quickMatch(QuickMatchRequest(requesterId: "me", boardSize: 8, timer: 20))
        #expect(ticket.status == .pending)
        let status = try await matcher.quickMatchStatus(ticketID: try #require(ticket.ticketId), requesterID: "me")
        #expect(status.action == .joinRoom)
        #expect(status.roomCode == 73055)   // the seeded 8×8 / 20 s bot room
        #expect(try await matcher.openRooms(boardSize: 8, timer: 20, limit: 10, offset: 0).map(\.roomCode) == [73055])
    }
}

/// Opt-in: two real sockets against the docker server.
/// `SQUAREOFF_LIVE_API=1 swift test --filter LiveSocket`
@Suite("Live socket (local server)", .enabled(if: ProcessInfo.processInfo.environment["SQUAREOFF_LIVE_API"] == "1"))
struct LiveSocketTests {
    @Test func hostAndGuestPlayFourMovesWithExactEchoes() async throws {
        let session = URLSession(configuration: .ephemeral)
        let host = LiveGameSocket(url: APIEnvironment.local.webSocketURL, session: session)
        let hostEvents = await EventReader(host)
        await host.connect()
        guard case .connected = await hostEvents.next() else { Issue.record("host did not connect (is the mkcert CA trusted and docker up?)"); return }
        try await host.send(.createRoom(player: seat(1, "iOS host"), boardSize: 6, timer: 0, gameID: nil, roomCode: nil))
        guard case let .roomCreated(created) = try await hostEvents.message("ROOM_CREATED", within: .seconds(5)) else { Issue.record("no room"); return }

        let guest = LiveGameSocket(url: APIEnvironment.local.webSocketURL, session: session)
        let guestEvents = await EventReader(guest)
        await guest.connect()
        try await guest.send(.requestPlayerSlot(roomCode: created.roomCode))
        guard case let .playerSlotAssigned(slot, _) = try await guestEvents.message("PLAYER_SLOT_ASSIGNED", within: .seconds(5)) else { Issue.record("no slot"); return }
        try await guest.send(.joinRoom(roomCode: created.roomCode, player: seat(slot, "iOS guest")))
        guard case let .gameState(lobby) = try await guestEvents.message("GAME_STATE", within: .seconds(5)) else { Issue.record("no state"); return }
        var game = try #require(Game(restoring: lobby, timerSeconds: 0))
        try await host.send(.gameStart)
        _ = try await guestEvents.message("GAME_START", within: .seconds(5))

        for (index, cell) in [Cell(row: 0, col: 0), Cell(row: 5, col: 5), Cell(row: 0, col: 1), Cell(row: 5, col: 4)].enumerated() {
            try await (index % 2 == 0 ? host : guest).send(.gameUpdate(cell: cell))
            guard case let .gameUpdate(update) = try await hostEvents.message("GAME_UPDATE", within: .seconds(5)) else { Issue.record("no echo"); return }
            _ = try await guestEvents.message("GAME_UPDATE", within: .seconds(5))
            try game.place(at: cell)
            #expect(game.matches(update.gameState))
        }
        try await guest.send(.gameUpdate(cell: Cell(row: 0, col: 0)))
        #expect(try await guestEvents.message("MOVE_REJECTED", within: .seconds(5)) == .moveRejected(reason: "not_your_turn"))
        await guest.close()
        await host.close()
    }
}
