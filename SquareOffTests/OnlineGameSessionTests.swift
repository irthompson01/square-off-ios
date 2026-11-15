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
        let matcher: MockMatcherAPI
        let backend: Backend
        var sessions: [OnlineGameSession] = []

        init(configuration: MockRoomServer.Configuration = .instant, api: (any SquareOffAPI)? = nil, ticketDelay: Duration = .zero) {
            server = MockRoomServer(configuration: configuration)
            matcher = MockMatcherAPI(server: server, ticketDelay: ticketDelay)
            backend = Backend(configuration: .mock, api: api ?? MockSquareOffAPI(latency: .zero),
                              matcher: matcher,
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

    /// Plays the game to the end, alternating whoever may tap.
    private func playOut(_ host: OnlineGameSession, _ guest: OnlineGameSession) async throws {
        while !host.isOver {
            let mover = host.canTap ? host : guest
            try await waitUntil { mover.canTap }
            mover.tap(CPUStrategy.maxMinOptimal.chooseMove(in: mover.game))
            let count = host.game.moves.count
            try await waitUntil { host.game.moves.count == count + 1 && guest.game.moves.count == count + 1 }
        }
    }

    @Test func fullGameThenHostResetsAndRestarts() async throws {
        let fixture = Fixture()
        let (host, guest, _, _) = try await startedGame(fixture, boardSize: 4)
        try await playOut(host, guest)
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

    @Test func sessionRecordGraceCountsFromLastSeen() throws {
        // A record written before `lastSeenAt` existed still decodes, and its grace counts from `savedAt`.
        let legacy = Data(#"{"roomCode":12345,"role":"guest","boardSize":8,"timerSeconds":0,"started":true,"savedAt":0,"backendID":"mock"}"#.utf8)
        let old = try JSONDecoder().decode(OnlineSessionRecord.self, from: legacy)
        #expect(old.lastSeenAt == nil)
        #expect(!old.isWithinGrace)
        var seen = old
        seen.lastSeenAt = Date()
        #expect(seen.isWithinGrace)
    }

    @Test func movesRefreshTheRejoinWindowWithoutMovingSavedAt() async throws {
        let fixture = Fixture()
        let (host, guest, _, _) = try await startedGame(fixture)
        var aged = try #require(OnlineSessionRecord.load())
        aged.lastSeenAt = Date(timeIntervalSinceNow: -100)
        UserDefaults.standard.set(try JSONEncoder().encode(aged), forKey: OnlineSessionRecord.key)
        #expect(OnlineSessionRecord.load()?.isWithinGrace == false)

        host.tap(Cell(row: 0, col: 0))
        try await waitUntil { host.game.moves.count == 1 && guest.game.moves.count == 1 }
        let refreshed = try #require(OnlineSessionRecord.load())
        #expect(refreshed.isWithinGrace)
        #expect(refreshed.savedAt == aged.savedAt)

        // A second move within a second is not written again.
        guest.tap(Cell(row: 1, col: 1))
        try await waitUntil { host.game.moves.count == 2 && guest.game.moves.count == 2 }
        #expect(OnlineSessionRecord.load()?.lastSeenAt == refreshed.lastSeenAt)
    }

    @Test func lostConnectionOffersReconnectAndRecovers() async throws {
        let fixture = Fixture()
        let (host, guest, _, _) = try await startedGame(fixture)
        guest.reconnectWindowOverride = .zero   // the window closes before the first attempt
        let socket = try #require(guest.debugSocket as? MockGameSocket)
        await socket.simulateDrop()
        try await waitUntil { guest.statusBanner == .lost }
        #expect(!guest.canTap)
        #expect(guest.notice == nil)

        host.tap(Cell(row: 2, col: 2))   // played while the guest is gone
        try await waitUntil { host.game.moves.count == 1 }
        guest.reconnect()
        try await waitUntil(.seconds(5)) { guest.connection == .online && guest.game.board[Cell(row: 2, col: 2)] == 1 }
        #expect(guest.statusBanner == nil)
        #expect(guest.canTap)
    }

    @Test func dropAfterGameOverStillReconnects() async throws {
        let fixture = Fixture()
        let (host, guest, _, _) = try await startedGame(fixture, boardSize: 4)
        try await playOut(host, guest)
        let socket = try #require(guest.debugSocket as? MockGameSocket)
        await socket.simulateDrop()
        try await waitUntil { guest.connection != .online }
        try await waitUntil(.seconds(5)) { guest.connection == .online }
        #expect(guest.isOver)

        host.restart()
        try await waitUntil { guest.rematchState == .waitingForHost }
    }

    @Test func failedResetSurfacesANotice() async throws {
        let fixture = Fixture()
        let (host, guest, _, _) = try await startedGame(fixture, boardSize: 4)
        try await playOut(host, guest)
        let socket = try #require(host.debugSocket as? MockGameSocket)
        await socket.failNextSend()
        host.restart()
        try await waitUntil { host.notice?.hasPrefix("Couldn't reset") == true }
        #expect(host.rematchState == .none)

        host.restart()   // the socket works again
        try await waitUntil { host.rematchState == .hostCanStart && guest.rematchState == .waitingForHost }
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

/// The lobby under bad conditions: cancels that race in-flight requests, flaky status polls,
/// a dropped lobby socket, and a seat update that never answers.
@MainActor
struct RoomCoordinatorResilienceTests {
    private func waitUntil(_ timeout: Duration = .seconds(3), _ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { throw OnlineGameSessionTests.TimeoutError() }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func isMatching(_ state: RoomCoordinator.State, withTicket: Bool) -> Bool {
        if case .matching(let ticket, _) = state { return withTicket == (ticket != nil) }
        return false
    }

    @Test func cancelDuringQuickMatchStaysIdle() async throws {
        let fixture = OnlineGameSessionTests.Fixture(ticketDelay: .milliseconds(300))
        OnlineSessionRecord.clear()
        let lobby = fixture.coordinator("Me")
        lobby.pollInterval = .milliseconds(50)
        await lobby.quickMatch(boardSize: 8, timer: 20)
        try await waitUntil { isMatching(lobby.state, withTicket: true) }
        await lobby.cancelQuickMatch()
        #expect(lobby.state == .idle)
        try await Task.sleep(for: .milliseconds(600))   // the ticket would have matched by now
        #expect(lobby.state == .idle)
        #expect(fixture.sessions.isEmpty)
        #expect(await fixture.matcher.openTicketCount == 0)
    }

    @Test func cancelWhileQuickMatchRequestInFlight() async throws {
        let fixture = OnlineGameSessionTests.Fixture()
        OnlineSessionRecord.clear()
        await fixture.matcher.setRequestDelay(.milliseconds(300))
        let lobby = fixture.coordinator("Me")
        let search = Task { await lobby.quickMatch(boardSize: 8, timer: 20) }
        try await Task.sleep(for: .milliseconds(50))
        await lobby.cancelQuickMatch()
        await search.value
        #expect(lobby.state == .idle)
        #expect(await fixture.matcher.openTicketCount == 0)
        #expect(fixture.sessions.isEmpty)
    }

    @Test func twoPollFailuresAreTolerated() async throws {
        var configuration = MockRoomServer.Configuration.instant
        configuration.botHostStartDelay = .milliseconds(50)
        let fixture = OnlineGameSessionTests.Fixture(configuration: configuration)
        OnlineSessionRecord.clear()
        await fixture.matcher.failNextStatusChecks(2)
        let lobby = fixture.coordinator("Me")
        lobby.pollInterval = .milliseconds(50)
        await lobby.quickMatch(boardSize: 8, timer: 20)
        try await waitUntil(.seconds(6)) { fixture.sessions.count == 1 }
    }

    @Test func threeFailuresCancelTheTicket() async throws {
        let fixture = OnlineGameSessionTests.Fixture(ticketDelay: .seconds(10))
        OnlineSessionRecord.clear()
        await fixture.matcher.failNextStatusChecks(3)
        let lobby = fixture.coordinator("Me")
        lobby.pollInterval = .milliseconds(50)
        await lobby.quickMatch(boardSize: 8, timer: 20)
        try await waitUntil { if case .failed = lobby.state { return true } else { return false } }
        #expect(lobby.state == .failed(.network("The game server is having trouble. Try again in a moment.")))
        #expect(await fixture.matcher.openTicketCount == 0)
    }

    @Test func matchTimeoutCancelsTheTicket() async throws {
        let fixture = OnlineGameSessionTests.Fixture(ticketDelay: .seconds(10))
        OnlineSessionRecord.clear()
        let lobby = fixture.coordinator("Me")
        lobby.pollInterval = .milliseconds(50)
        lobby.matchWindow = .milliseconds(300)
        await lobby.quickMatch(boardSize: 8, timer: 20)
        try await waitUntil { lobby.state == .failed(.matchTimeout) }
        #expect(await fixture.matcher.openTicketCount == 0)
    }

    @Test func lobbyDropShowsReconnectingThenClears() async throws {
        var configuration = MockRoomServer.Configuration.instant
        configuration.hostGrace = .seconds(10)   // `.instant` closes a hostless room at once
        let fixture = OnlineGameSessionTests.Fixture(configuration: configuration)
        OnlineSessionRecord.clear()
        let hostLobby = fixture.coordinator("Host")
        await hostLobby.host(boardSize: 4, timer: 0, listPublic: false)
        try await waitUntil { hostLobby.state.roomInfo != nil }
        let code = try #require(hostLobby.state.roomInfo?.code)
        let socket = try #require(hostLobby.debugSocket as? MockGameSocket)
        await socket.simulateDrop()
        try await waitUntil { hostLobby.reconnectAttempt != nil }
        try await waitUntil(.seconds(5)) { hostLobby.reconnectAttempt == nil && hostLobby.state.roomInfo != nil }

        let guestLobby = fixture.coordinator("Guest")
        await guestLobby.join(code: code)
        try await waitUntil { hostLobby.state.roomInfo?.seats.count == 2 }
    }

    @Test func cancelStartRevertsAndSuppressesGameStart() async throws {
        let api = SpyAPI()
        await api.setDelay("updatePlayers", .seconds(30))
        let fixture = OnlineGameSessionTests.Fixture(api: api)
        OnlineSessionRecord.clear()
        let hostLobby = fixture.coordinator("Host")
        await hostLobby.host(boardSize: 4, timer: 0, listPublic: false)
        try await waitUntil { hostLobby.state.roomInfo != nil }
        let guestLobby = fixture.coordinator("Guest")
        await guestLobby.join(code: try #require(hostLobby.state.roomInfo?.code))
        try await waitUntil { hostLobby.state.roomInfo?.seats.count == 2 }

        let starting = Task { await hostLobby.startGame() }
        try await waitUntil { if case .starting = hostLobby.state { return true } else { return false } }
        hostLobby.cancelStart()
        #expect(hostLobby.state.roomInfo != nil)
        if case .starting = hostLobby.state { Issue.record("still starting") }
        try await Task.sleep(for: .milliseconds(400))
        #expect(fixture.sessions.isEmpty)
        starting.cancel()
    }

    @Test func slowUpdatePlayersTimesOutAndStillStarts() async throws {
        let api = SpyAPI()
        await api.setDelay("updatePlayers", .seconds(30))
        let fixture = OnlineGameSessionTests.Fixture(api: api)
        OnlineSessionRecord.clear()
        let hostLobby = fixture.coordinator("Host")
        await hostLobby.host(boardSize: 4, timer: 0, listPublic: false)
        try await waitUntil { hostLobby.state.roomInfo != nil }
        let guestLobby = fixture.coordinator("Guest")
        await guestLobby.join(code: try #require(hostLobby.state.roomInfo?.code))
        try await waitUntil { hostLobby.state.roomInfo?.seats.count == 2 }
        hostLobby.startTimeout = .milliseconds(200)
        await hostLobby.startGame()
        try await waitUntil(.seconds(2)) { fixture.sessions.count == 2 }
    }
}

/// What the lobby tells the user when the server misbehaves.
@MainActor
struct OnlineErrorCopyTests {
    @Test func serverAndProxyErrorsReadAsSentences() {
        #expect(RoomCoordinator.describe(APIError.http(status: 503, body: "<html>bad gateway</html>")) == "The game server is having trouble. Try again in a moment.")
        #expect(RoomCoordinator.describe(APIError.http(status: 429, body: "")) == "Too many attempts. Try again in a minute.")
        #expect(RoomCoordinator.describe(APIError.http(status: 400, body: #"{"detail":"rate_limited"}"#)) == "Too many attempts. Try again in a minute.")
        #expect(RoomCoordinator.describe(APIError.http(status: 404, body: #"{"detail":"room_not_found"}"#)) == "That room doesn't exist (or was closed).")
        #expect(RoomCoordinator.describe(APIError.http(status: 400, body: #"{"detail":"weird_code"}"#)) == "Something went wrong talking to the game server. Try again.")
        #expect(RoomCoordinator.describe(APIError.http(status: 404, body: #"{"detail":"Room not found"}"#)) == "Room not found")
        #expect(RoomCoordinator.describe(APIError.http(status: 404, body: "")) == "That room or match couldn't be found.")
        #expect(RoomCoordinator.describe(APIError.timeout) == "The server didn't answer in time.")
        #expect((APIError.http(status: 500, body: "") as Error).localizedDescription == "The game server is having trouble. Try again in a moment.")
        #expect((APIError.http(status: 400, body: #"{"detail":"x_code"}"#) as Error).localizedDescription == "Something went wrong (HTTP 400).")
    }
}

/// Session rules from the 2026-11 server: the host's clock skips every seat, and a refused
/// handshake is recovered once with a fresh guest session.
@MainActor
struct OnlineSessionRulesTests {
    private func waitUntil(_ timeout: Duration = .seconds(3), _ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { throw OnlineGameSessionTests.TimeoutError() }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func theHostsClockSkipsEverySeatAndGuestsStayQuiet() async throws {
        let fixture = OnlineGameSessionTests.Fixture()
        OnlineSessionRecord.clear()
        let hostLobby = fixture.coordinator("Host")
        await hostLobby.host(boardSize: 4, timer: 1, listPublic: false)
        try await waitUntil { hostLobby.state.roomInfo != nil }
        let code = try #require(hostLobby.state.roomInfo?.code)
        let guestLobby = fixture.coordinator("Guest")
        await guestLobby.join(code: code)
        try await waitUntil { hostLobby.state.roomInfo?.seats.count == 2 && guestLobby.state.roomInfo != nil }
        await hostLobby.startGame()
        try await waitUntil { fixture.sessions.count == 2 }
        let host = try #require(fixture.sessions.first { $0.capabilities.canRestart })
        let guest = try #require(fixture.sessions.first { !$0.capabilities.canRestart })
        await host.start()
        await guest.start()
        // Nobody taps: the host's own second expires (move 1), then the guest's (move 2), both
        // completed by the host's socket. The guest's timer never sends anything.
        try await waitUntil(.seconds(6)) { host.game.moves.count >= 2 && guest.game.moves.count >= 2 }
        #expect(host.game.moves[0].playerID == 1 && host.game.moves[1].playerID == 2)
        // Both sessions save to the same defaults; whichever wrote last, the record names its session.
        #expect(["id-Host", "id-Guest"].contains(OnlineSessionRecord.load()?.playerID ?? ""))
        host.stop(); guest.stop()
    }

    @Test func aRefusedHandshakeIsRecoveredOnceThroughTheIdentityStore() async throws {
        let fixture = OnlineGameSessionTests.Fixture()
        OnlineSessionRecord.clear()
        let transport = fixture.backend.makeOnlineTransport()
        let socket = try #require(transport.connection.socket as? MockGameSocket)
        await socket.refuseNextConnect(code: 1008, reason: "session_required")
        try await transport.connection.connect()   // recovery mints a guest and connects again
        #expect(transport.connection.isConnected)
        #expect(fixture.backend.guestTokens.accessToken() != nil)

        let again = fixture.backend.makeOnlineTransport()
        let blocked = try #require(again.connection.socket as? MockGameSocket)
        await blocked.refuseNextConnect(code: 1008, reason: "origin_not_allowed")
        await #expect(throws: SocketError.self) { try await again.connection.connect() }
    }
}
