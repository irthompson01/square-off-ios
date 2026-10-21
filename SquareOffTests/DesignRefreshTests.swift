import Foundation
import SquareOffCore
import SquareOffNet
import Testing
@testable import SquareOff

/// Helpers and models added with the web design refresh.
@MainActor
struct DesignRefreshTests {
    private func config(_ mode: GameConfig.Mode = .passAndPlay) -> GameConfig {
        GameConfig(mode: mode, boardSize: 6, timerSeconds: 0, players: [
            SetupPlayer(id: 1, name: "A", colorHex: Theme.playerColors[0]),
            SetupPlayer(id: 2, name: "B", colorHex: Theme.playerColors[1]),
        ])
    }

    @Test func localGameRoundTripsAndRestoresByReplayingMoves() throws {
        let defaults = UserDefaults(suiteName: "DesignRefreshTests.\(UUID().uuidString)")!
        let store = LocalGameStore(defaults: defaults)
        let snapshot = LocalGameStore.Snapshot(config: config(.cpu(.maxMin)), moves: [Cell(row: 0, col: 0), Cell(row: 5, col: 5)], savedAt: .now)
        store.save(snapshot)
        #expect(store.load() == snapshot)

        let restored = try #require(GameSession(restoring: snapshot))
        #expect(restored.game.moves.count == 2)
        #expect(restored.game.board[Cell(row: 0, col: 0)] == 1)
        #expect(restored.currentPlayer.id == 1)
        #expect(restored.config.mode == .cpu(.maxMin))

        store.clear()
        #expect(store.load() == nil)
        // A snapshot whose moves don't replay (occupied tile) is rejected.
        #expect(GameSession(restoring: LocalGameStore.Snapshot(config: config(), moves: [Cell(row: 0, col: 0), Cell(row: 0, col: 0)], savedAt: .now)) == nil)
    }

    @Test func gameSessionPersistsMovesAndClearsWhenLeft() async throws {
        let defaults = UserDefaults(suiteName: "DesignRefreshTests.\(UUID().uuidString)")!
        let store = LocalGameStore(defaults: defaults)
        let session = GameSession(config: config(), store: store)
        await session.start()
        session.tap(Cell(row: 1, col: 1))
        try await Task.sleep(for: .milliseconds(250))
        #expect(store.load()?.moves == [Cell(row: 1, col: 1)])
        #expect(session.savedAt != nil)
        session.leave()
        #expect(store.load() == nil)
    }

    @Test func setupResolvesNamesAndWarnsAboutSharedColours() {
        let setup = PlaySetupModel()
        setup.mode = .local
        setup.playerCount = 3
        setup.setName("   ", forSeat: 0)
        setup.setName(String(repeating: "x", count: 40), forSeat: 1)
        let resolved = setup.resolvedPlayers
        #expect(resolved.count == 3)
        #expect(resolved[0].name == "Player 1")
        #expect(resolved[1].name.count == PlaySetupModel.maxNameLength)
        #expect(setup.duplicateColorWarning == nil)

        setup.players[1].colorHex = setup.players[0].colorHex.lowercased()
        #expect(setup.duplicateColorWarning == "Players 1 and 2 share a color. Pick different colors so tiles are easy to tell apart.")
        setup.players[2].colorHex = setup.players[0].colorHex
        #expect(setup.duplicateColorWarning?.hasPrefix("Players 1, 2 and 3 share a color.") == true)
        setup.playerCount = 2
        setup.players[1].colorHex = Theme.playerColors[1]
        #expect(setup.duplicateColorWarning == nil)   // seat 3 is hidden now
    }

    @Test func setupPrimaryActionFollowsModeAndTab() {
        let setup = PlaySetupModel()
        #expect(setup.primaryTitle == "Start Game")
        setup.mode = .local
        #expect(setup.primaryTitle == "Start Local Game")
        setup.mode = .online
        #expect(setup.primaryTitle == "Create Room")
        setup.onlineTab = .quick
        #expect(setup.primaryTitle == "Find a Match")
        setup.onlineTab = .join
        #expect(setup.primaryTitle == "Join Room")
        setup.onlineTab = .rooms
        #expect(setup.primaryTitle == nil)
        #expect(setup.timer == 0 && setup.boardSize == 8 && setup.level == .random && setup.listPublic == false)
    }

    @Test func joinCodeAcceptsOnlyOneToSixDigits() {
        let setup = PlaySetupModel()
        setup.joinCode = "12ab34567"
        setup.sanitizeJoinCode()
        #expect(setup.joinCode == "123456")
        #expect(setup.isJoinCodeValid)
        setup.joinCode = ""
        #expect(!setup.isJoinCodeValid)
    }

    @Test func colourNamesUsePresetsThenHue() {
        #expect(ColorNames.name(for: "#4c8bf5") == "Blue")
        #expect(ColorNames.name(for: "#DD5144") == "Red")
        #expect(ColorNames.name(for: "#FF8800") == "Orange")
        #expect(ColorNames.name(for: "#00FFFF") == "Teal")
        #expect(ColorNames.name(for: "#777777") == "Grey")
        #expect(ColorNames.name(for: "nope") == "Not set")
    }

    @Test func relativeAgoMatchesTheWebBuckets() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(RelativeAgo.coarse(now - 30, now: now) == "just now")
        #expect(RelativeAgo.coarse(now - 180, now: now) == "3 min ago")
        #expect(RelativeAgo.coarse(now - 7200, now: now) == "2 h ago")
        #expect(RelativeAgo.coarse(now - 90_000, now: now) == "earlier")
        #expect(RelativeAgo.fine(now - 5, now: now) == "just now")
        #expect(RelativeAgo.fine(now - 20, now: now) == "20s ago")
        #expect(RelativeAgo.fine(now - 125, now: now) == "2 min ago")
    }

    @Test func paginationUsesSevenSlots() {
        #expect(Pagination.slots(current: 0, pages: 3) == [0, 1, 2])
        #expect(Pagination.slots(current: 0, pages: 9) == [0, 1, 2, 3, 4, nil, 8])
        #expect(Pagination.slots(current: 4, pages: 9) == [0, nil, 3, 4, 5, nil, 8])
        #expect(Pagination.slots(current: 8, pages: 9) == [0, nil, 4, 5, 6, 7, 8])
    }

    @Test func cpuRowsAggregateLikeTheWeb() {
        func row(_ type: String, games: Int, won: Int, high: Int, avg: Double, duration: Double) -> PlayerStatsCPUView {
            PlayerStatsCPUView(playerId: "p", username: "u", cpuType: type, totalGamesPlayed: games, gamesWon: won, gamesLost: games - won,
                               winPercentage: Double(won) / Double(games) * 100, avgGameDuration: duration, highestScore: high,
                               avgFinalScore: avg, localGamesPlayed: games)
        }
        let combined = StatsSummary.combine([row("random", games: 3, won: 3, high: 50, avg: 40, duration: 10),
                                             row("cnn", games: 1, won: 0, high: 80, avg: 20, duration: 30)])
        #expect(combined?.games == 4 && combined?.wins == 3 && combined?.losses == 1)
        #expect(combined?.winPercentage == 75)
        #expect(combined?.highScore == 80)
        #expect(combined?.avgScore == 35)          // (40×3 + 20×1) / 4
        #expect(combined?.avgDurationMinutes == 20) // plain mean of the rows
        #expect(StatsSummary.combine([]) == nil)
    }

    @Test func oauthErrorCodesMapToTheWebMessages() {
        #expect(OAuthCallback.message(for: "apple_cancelled") == "Apple sign-in was cancelled.")
        #expect(OAuthCallback.message(for: "github_failed") == "GitHub sign-in failed. Please try again.")
        #expect(OAuthCallback.message(for: "google_expired") == "Your Google sign-in session expired. Please try again.")
        #expect(OAuthCallback.message(for: "apple_no_email").hasPrefix("Apple didn't share an email"))
        #expect(OAuthCallback.message(for: "weird") == "Sign-in failed. Please try again.")
        #expect(OAuthCallback.errorCode(from: URL(string: "squareoff://auth?error=apple_failed")!) == "apple_failed")
    }
}
