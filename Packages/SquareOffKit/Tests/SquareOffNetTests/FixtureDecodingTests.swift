import Foundation
import Testing
import SquareOffCore
@testable import SquareOffNet

private func fixture(_ name: String, in subdirectory: String = "Fixtures") throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: subdirectory))
    return try Data(contentsOf: url)
}

private func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
    try JSONDecoder().decode(type, from: fixture(name))
}

/// REST responses captured from the docker server (branch feature/ios-integration) with a bearer token.
@Suite("Decoding captured REST responses")
struct RESTFixtureTests {
    @Test func login() throws {
        let response = try decode(LoginResponse.self, "login_response")
        #expect(response.tokenType == "bearer")
        #expect(response.accessToken != nil)
    }

    @Test func checkAuthAndProfile() throws {
        let auth = try decode(CheckAuthResponse.self, "check_auth")
        #expect(auth.authenticated)
        let profile = try decode(ProfileResponse.self, "profile")
        #expect(profile.username == "contract_ios")
        #expect(profile.id == auth.userId)
        #expect(profile.appRole == "standard")
        #expect(profile.displayName == "contract_ios")   // no first/last name set
    }

    @Test func createGuest() throws {
        let guest = try decode(CreateGuestResponse.self, "create_guest_response")
        #expect(guest.playerId.count == 36)
    }

    @Test func oauthLoginForIOS() throws {
        let login = try decode(OAuthLoginResponse.self, "oauth_login_ios")
        #expect(login.url.host == "accounts.google.com")
    }

    @Test func startGameForUser() throws {
        let start = try decode(StartGameResponse.self, "start_game_response_user")
        #expect(start.participants.count == 2)
    }

    @Test func stats() throws {
        let stats = try decode(PlayerStatsView.self, "stats_view")
        #expect(stats.totalGamesPlayed >= 1)
        #expect(stats.winPercentage <= 100)
        let cpu = try decode([PlayerStatsCPUView].self, "stats_view_cpu")
        #expect(cpu.first?.cpuType == "max-min")
        let human = try decode(PlayerStatsView.self, "stats_view_human")
        #expect(human.username == stats.username)
        let filters = try decode(ProfileStatsFilters.self, "profile_stats_filters")
        #expect(filters.boardSizes.contains(6))
    }

    @Test func recentGamesAndReplay() throws {
        let page = try decode(RecentGamesPage.self, "recent_games")
        #expect(page.total >= 1)
        #expect(page.games.first?.result == "W")
        #expect(page.games.first?.opponentLabel == "CPU (max-min)")
        let replay = try decode(GameReplayPayload.self, "replay")
        #expect(replay.boardSize == 6)
        #expect(replay.turns.count == 36)
        #expect(replay.participants.map(\.boardSlotId) == [1, 2])
        #expect(replay.participants.last?.participantType == "cpu")
        // Every replay turn is a legal move when replayed in order.
        var game = Game(boardSize: 6, players: replay.participants.map {
            PlayerState(id: $0.boardSlotId, name: $0.displayName, colorHex: $0.color, isCPU: $0.participantType == "cpu")
        })
        for turn in replay.turns {
            #expect(game.currentPlayer.id == turn.boardSlotId)
            try game.place(at: turn.cell)
        }
        #expect(game.isOver)
    }

    @Test func cnnMove() throws {
        let move = try decode(CPUMoveResponse.self, "cpu_move_cnn_response")
        #expect((0..<8).contains(move.row) && (0..<8).contains(move.col))
    }
}

/// Socket messages captured by scripts/capture_ws_fixtures.py (host + guest + spectator session).
@Suite("Decoding captured WebSocket messages")
struct WSDecodingTests {
    private func message(_ name: String) throws -> ServerMessage {
        try ServerMessage.decode(try fixture(name, in: "Fixtures/ws"))
    }

    @Test func everyCapturedMessageIsKnown() throws {
        let urls = try #require(Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Fixtures/ws"))
        #expect(urls.count >= 20)
        for url in urls {
            let decoded = try ServerMessage.decode(try Data(contentsOf: url))
            if case .unknown = decoded { Issue.record("unknown type in \(url.lastPathComponent)") }
        }
    }

    @Test func lobbyMessages() throws {
        guard case let .roomCreated(created) = try message("ROOM_CREATED_1") else { Issue.record("ROOM_CREATED"); return }
        #expect(created.boardSize == 6 && created.timer == 20)
        guard case let .playerSlotAssigned(slot, color) = try message("PLAYER_SLOT_ASSIGNED_1") else { Issue.record("PLAYER_SLOT_ASSIGNED"); return }
        #expect(slot == 2 && color?.hasPrefix("#") == true)   // colour comes from the server's DEFAULT_COLORS env
        guard case let .playerJoined(joined) = try message("PLAYER_JOINED_1") else { Issue.record("PLAYER_JOINED"); return }
        #expect(joined?.id == 2 && joined?.isCPU == false)
        guard case let .gameState(lobby) = try message("GAME_STATE_1") else { Issue.record("GAME_STATE"); return }
        #expect(lobby.seats.map(\.id) == [1, 2])
        #expect(!lobby.gameState.looksInProgress)
        #expect(try message("GAME_START_1") == .gameStart(spectatorCount: 0))
    }

    @Test func gameUpdatesReplayExactly() throws {
        guard case let .gameState(lobby) = try message("GAME_STATE_1") else { Issue.record("GAME_STATE"); return }
        var game = try #require(Game(restoring: lobby, timerSeconds: 20))
        for n in 1...7 {
            guard case let .gameUpdate(update) = try message("GAME_UPDATE_\(n)") else { Issue.record("GAME_UPDATE_\(n)"); return }
            let cell = try #require(update.gameState.moveCell)
            let result = try game.place(at: cell)
            #expect(game.matches(update.gameState), "update \(n) diverged")
            if n == 7 {
                #expect(result.newShapes.count == 1)
                #expect(update.gameState.newShapes?.count == 1)
                #expect(update.gameState.newShapes?.all.first == result.newShapes.first)
                #expect(update.gameState.players?.first?.currentScore == 4)
                #expect(update.gameState.players?.first?.scoreHistory?.count == 7)
            }
            // A full rebuild from the same snapshot agrees too.
            let rebuilt = try #require(Game(restoring: update, timerSeconds: 20))
            #expect(rebuilt.matches(update.gameState))
            #expect(rebuilt.players.map(\.score) == game.players.map(\.score))
        }
        // TURN_COMPLETE: a random legal move by the current player.
        guard case let .gameUpdate(random) = try message("GAME_UPDATE_8") else { Issue.record("GAME_UPDATE_8"); return }
        let cell = try #require(random.gameState.moveCell)
        try game.place(at: cell)
        #expect(game.matches(random.gameState))
    }

    @Test func rejectionsAndRoomLifecycle() throws {
        #expect(try message("MOVE_REJECTED_1") == .moveRejected(reason: "not_your_turn"))
        #expect(try message("MOVE_REJECTED_2") == .moveRejected(reason: "occupied"))
        guard case let .gameState(spectating) = try message("GAME_STATE_2") else { Issue.record("GAME_STATE_2"); return }
        #expect(spectating.gameState.looksInProgress)
        #expect(spectating.spectatorCount == 1)
        #expect(try message("SPECTATOR_COUNT_1") == .spectatorCount(1))
        guard case let .promotedToPlayer(promotedID, promotedColor) = try message("PROMOTED_TO_PLAYER_1") else { Issue.record("PROMOTED_TO_PLAYER"); return }
        #expect(promotedID == 3 && promotedColor?.hasPrefix("#") == true)
        guard case let .gameReset(reset) = try message("GAME_RESET_1") else { Issue.record("GAME_RESET"); return }
        #expect(reset.players.map(\.id) == [1, 2, 3])
        #expect(reset.players.allSatisfy { ($0.currentScore ?? 0) == 0 })
        #expect(try message("GUEST_AWAY_1") == .guestAway(playerId: 2))
        #expect(try message("HOST_AWAY_1") == .hostAway)
    }
}
