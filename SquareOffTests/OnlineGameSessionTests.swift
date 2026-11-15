import Foundation
import SquareOffCore
import SquareOffNet
import Testing
@testable import SquareOff

/// Two coordinators (host and guest) against one in-process room server, as two devices would be.
@MainActor
struct OnlineGameSessionTests {
    final class Fixture {
        let server: MockRoomServer
        let backend: Backend
        var sessions: [OnlineGameSession] = []

        init(configuration: MockRoomServer.Configuration = .instant) {
            server = MockRoomServer(configuration: configuration)
            backend = Backend(configuration: .mock, api: MockSquareOffAPI(latency: .zero),
                              matcher: MockMatcherAPI(server: server, ticketDelay: .zero),
                              tokenStore: InMemoryTokenStore(), roomServer: server,
                              defaults: UserDefaults(suiteName: "SquareOffTests.online.\(UUID().uuidString)")!)
        }

        func coordinator(_ name: String) -> RoomCoordinator {
            let coordinator = RoomCoordinator(
                makeTransport: { [backend] in backend.makeOnlineTransport() },
                identityProvider: { Identity(playerID: "id-\(name)", displayName: name, colorHex: "#0583D2") })
            coordinator.onPlay = { [weak self] session in self?.sessions.append(session) }
            return coordinator
        }
    }

    private func waitUntil(_ timeout: Duration = .seconds(3), _ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { throw TimeoutError() }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    struct TimeoutError: Error {}

    /// Host creates a room, guest joins by code, host starts: both end up with a session.
    private func startedGame(_ fixture: Fixture, boardSize: Int = 4) async throws -> (host: OnlineGameSession, guest: OnlineGameSession, hostLobby: RoomCoordinator, guestLobby: RoomCoordinator) {
        OnlineSessionRecord.clear()
        let hostLobby = fixture.coordinator("Host")
        await hostLobby.host(boardSize: boardSize, timer: 0, listPublic: true)
        try await waitUntil { hostLobby.state.roomInfo != nil }
        let code = try #require(hostLobby.state.roomInfo?.code)

        let guestLobby = fixture.coordinator("Guest")
        await guestLobby.join(code: code)
        try await waitUntil { hostLobby.state.roomInfo?.seats.count == 2 && guestLobby.state.roomInfo != nil }
        #expect(guestLobby.state.roomInfo?.mySeat == 2)
        #expect(guestLobby.state.roomInfo?.role == .guest)

        await hostLobby.startGame()
        try await waitUntil { fixture.sessions.count == 2 }
        let host = try #require(fixture.sessions.first { $0.capabilities.canRestart })
        let guest = try #require(fixture.sessions.first { !$0.capabilities.canRestart })
        await host.start()
        await guest.start()
        return (host, guest, hostLobby, guestLobby)
    }

    @Test func hostAndGuestReachPlayAndMovesEchoToBoth() async throws {
        let fixture = Fixture()
        let (host, guest, _, _) = try await startedGame(fixture)
        #expect(host.canTap && !guest.canTap)
        #expect(guest.turnLabel == "Host's turn")
        #expect(guest.isCPUThinking)   // "waiting for the other player"

        host.tap(Cell(row: 0, col: 0))
        try await waitUntil { host.game.moves.count == 1 && guest.game.moves.count == 1 }
        #expect(host.spins[Cell(row: 0, col: 0)] == nil && host.lastMove?.cell == Cell(row: 0, col: 0))
        #expect(guest.lastMove?.cell == Cell(row: 0, col: 0))
        #expect(guest.canTap && !host.canTap)
        #expect(host.turnLabel == "Guest's turn" && guest.turnLabel == "Your turn")

        guest.tap(Cell(row: 0, col: 0))   // occupied: ignored locally, nothing sent
        guest.tap(Cell(row: 1, col: 1))
        try await waitUntil { host.game.moves.count == 2 }
        #expect(host.game.board[Cell(row: 1, col: 1)] == 2)
        #expect(host.visibleShapes.isEmpty)
    }

    @Test func fullGameThenHostResetsAndRestarts() async throws {
        let fixture = Fixture()
        let (host, guest, _, _) = try await startedGame(fixture, boardSize: 4)
        while !host.isOver {
            let mover = host.canTap ? host : guest
            try await waitUntil { mover.canTap }
            mover.tap(CPUStrategy.maxMinOptimal.chooseMove(in: mover.game))
            let count = host.game.moves.count
            try await waitUntil { host.game.moves.count == count + 1 && guest.game.moves.count == count + 1 }
        }
        #expect(guest.isOver)
        #expect(host.game.players.map(\.score) == guest.game.players.map(\.score))
        #expect(host.rematchState == .none && guest.rematchState == .none)

        host.restart()
        try await waitUntil { host.rematchState == .hostCanStart && guest.rematchState == .waitingForHost }
        #expect(host.game.board.emptyCells.count == 16)
        #expect(!host.canTap && !guest.canTap)

        host.startRematch()
        try await waitUntil { host.canTap }
        #expect(guest.rematchState == .none)
        #expect(guest.turnLabel == "Host's turn")
    }

    @Test func lateJoinerSpectatesAndCannotTap() async throws {
        let fixture = Fixture()
        let (host, _, hostLobby, _) = try await startedGame(fixture)
        let watcher = fixture.coordinator("Watcher")
        await watcher.join(code: try #require(hostLobby.state.roomInfo?.code ?? host.capabilities.roomCode))
        try await waitUntil { fixture.sessions.count == 3 }
        let spectator = try #require(fixture.sessions.last)
        #expect(spectator.capabilities.isSpectator)
        #expect(!spectator.canTap)
        #expect(spectator.turnLabel.hasPrefix("Spectating"))
        host.tap(Cell(row: 0, col: 0))
        try await waitUntil { spectator.game.board[Cell(row: 0, col: 0)] == 1 }
    }

    @Test func droppedGuestReconnectsAndCatchesUp() async throws {
        let fixture = Fixture()
        let (host, guest, _, _) = try await startedGame(fixture)
        let socket = try #require(guest.debugSocket as? MockGameSocket)
        await socket.simulateDrop()
        try await waitUntil { guest.connectionLabel != nil }
        #expect(!guest.canTap)

        host.tap(Cell(row: 2, col: 2))   // played while the guest is away
        try await waitUntil(.seconds(5)) { guest.connectionLabel == nil }   // reconnect + REJOIN_ROOM
        try await waitUntil { guest.game.board[Cell(row: 2, col: 2)] == 1 }
        #expect(guest.canTap)
        guest.tap(Cell(row: 3, col: 3))
        try await waitUntil { host.game.moves.count == 2 }
    }

    @Test func quickMatchLandsInABotRoomThatStartsItself() async throws {
        var configuration = MockRoomServer.Configuration.instant
        configuration.botHostStartDelay = .milliseconds(50)
        let fixture = Fixture(configuration: configuration)
        OnlineSessionRecord.clear()
        let lobby = fixture.coordinator("Me")
        await lobby.quickMatch(boardSize: 8, timer: 20)
        try await waitUntil(.seconds(6)) { fixture.sessions.count == 1 }
        let session = try #require(fixture.sessions.first)
        #expect(session.capabilities.roomCode == 73055)
        #expect(session.game.players.first?.isCPU == true)
        #expect(session.game.players.count == 2)
        #expect(!session.capabilities.canRestart)
    }
}
