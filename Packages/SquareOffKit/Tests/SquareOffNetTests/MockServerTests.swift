import Foundation
import Testing
import SquareOffCore
@testable import SquareOffNet

/// The mock must behave like the docker server for every flow the app drives.
@Suite("Mock server")
struct MockServerTests {
    private func api() -> MockSquareOffAPI { MockSquareOffAPI(latency: .zero) }

    @Test func demoAccountHasSeededHistory() async throws {
        let api = api()
        let login = try await api.login(LoginRequest(emailOrUsername: MockSquareOffAPI.demoUsername, password: MockSquareOffAPI.demoPassword))
        #expect(login.accessToken == MockSquareOffAPI.token(for: "demo"))
        #expect(try await api.checkAuth())
        let profile = try await api.profile()
        #expect(profile.username == "demo")
        let stats = try await api.statsView()
        #expect(stats.totalGamesPlayed == 3)
        #expect(stats.gamesWon + stats.gamesLost == 3)
        let recent = try await api.recentGames(limit: 10, offset: 0)
        #expect(recent.total == 3)
        #expect(recent.games.first?.opponentLabel == "Guest, Guest")   // newest first
        let cpu = try await api.statsViewCPU(boardSize: nil, timer: nil, cpuType: nil)
        #expect(Set(cpu.map(\.cpuType)) == ["max-min", "cnn"])
        let replay = try await api.replay(gameID: try #require(recent.games.last?.gameId))
        #expect(replay.boardSize == 8)
        #expect(replay.turns.count == 64)
        #expect(replay.turns.first?.boardSlotId == 1)
    }

    @Test func deletingTheAccountEndsTheSessionAndFreesTheEmail() async throws {
        let api = api()
        _ = try await api.register(RegisterRequest(username: "gone", email: "gone@example.com", password: "secret123"))
        _ = try await api.login(LoginRequest(emailOrUsername: "gone", password: "secret123"))
        #expect(try await api.deleteAccount(AccountDeleteRequest()).message == "Account deleted")
        await #expect(throws: APIError.self) { _ = try await api.profile() }
        await #expect(throws: APIError.self) {
            _ = try await api.login(LoginRequest(emailOrUsername: "gone", password: "secret123"))
        }
        _ = try await api.register(RegisterRequest(username: "gone2", email: "gone@example.com", password: "secret123"))
    }

    @Test func passwordResetFlow() async throws {
        let api = api()
        _ = try await api.requestPasswordReset(email: "nobody@example.com")   // same answer, no token
        await #expect(throws: APIError.self) {
            _ = try await api.resetPassword(token: MockSquareOffAPI.demoResetToken, newPassword: "longenough1")
        }
        _ = try await api.requestPasswordReset(email: "demo@squareoff.app")
        await #expect(throws: APIError.self) {
            _ = try await api.resetPassword(token: MockSquareOffAPI.demoResetToken, newPassword: "short")
        }
        _ = try await api.resetPassword(token: MockSquareOffAPI.demoResetToken, newPassword: "longenough1")
        _ = try await api.login(LoginRequest(emailOrUsername: MockSquareOffAPI.demoUsername, password: "longenough1"))
        // The link is single use.
        await #expect(throws: APIError.self) {
            _ = try await api.resetPassword(token: MockSquareOffAPI.demoResetToken, newPassword: "longenough2")
        }
    }

    @Test func feedbackIsValidatedAndKept() async throws {
        let api = api()
        await #expect(throws: APIError.self) { _ = try await api.sendFeedback(FeedbackRequest(subject: "", message: "x")) }
        let sent = try await api.sendFeedback(FeedbackRequest(subject: "Board", message: "Tiles overlap", contactEmail: nil, displayName: "Pat"))
        #expect(sent.id == 1 && sent.emailed == true)
        #expect(await api.feedbackInbox.count == 1)
    }

    @Test func wrongPasswordIs401AndGuestsAreNotAuthenticated() async throws {
        let api = api()
        #expect(try await api.checkAuth() == false)
        await #expect(throws: APIError.self) {
            _ = try await api.login(LoginRequest(emailOrUsername: "demo", password: "nope"))
        }
        await #expect(throws: APIError.self) { _ = try await api.profile() }
    }

    @Test func registerLoginRecordEndShowsUpInStats() async throws {
        let api = api()
        let registered = try await api.register(RegisterRequest(username: "ian", email: "ian@example.com", password: "secret123"))
        await #expect(throws: APIError.self) {
            _ = try await api.register(RegisterRequest(username: "ian", email: "other@example.com", password: "x"))
        }
        _ = try await api.login(LoginRequest(emailOrUsername: "ian@example.com", password: "secret123"))

        let cpu = try await api.cpuPlayer(.maxMin)
        let seats = [
            StartPlayer(id: 1, name: "Ian", color: "#0583D2", playerId: registered.playerId, isCPU: false, cpuType: nil),
            StartPlayer(id: 2, name: cpu.displayName, color: "#FF3131", playerId: String(cpu.id), isCPU: true, cpuType: cpu.cpuType),
        ]
        let start = try await api.startGame(StartGameRequest(boardSize: 6, timer: 0, seats: seats, type: .local))
        #expect(start.participants.count == 2)
        let participants = Dictionary(uniqueKeysWithValues: zip([1, 2], start.participants.map(\.participantId)))

        var game = Game(boardSize: 6, players: [
            PlayerState(id: 1, name: "Ian", colorHex: "#0583D2"),
            PlayerState(id: 2, name: "CPU", colorHex: "#FF3131", isCPU: true, cpuLevel: .maxMin),
        ])
        while !game.isOver {
            let mover = game.currentPlayer
            let cell = CPUStrategy.maxMin.chooseMove(in: game)
            let move = try game.place(at: cell)
            _ = try await api.insertTurn(gameID: start.gameId, GameTurnRequest(move: move, player: mover, playerID: seats[mover.id - 1].playerId, participantID: participants[mover.id]))
        }
        let winner = game.isDraw ? "" : seats[game.standings[0].id - 1].playerId!
        try await api.endGame(GameEndRequest(gameId: start.gameId, winnerId: winner, scores: game.players.map {
            ScoreEntry(playerId: seats[$0.id - 1].playerId!, score: $0.score)
        }))
        await #expect(throws: APIError.self) {   // ending twice is a 404, like the server
            try await api.endGame(GameEndRequest(gameId: start.gameId, winnerId: winner, scores: []))
        }

        let stats = try await api.statsView()
        #expect(stats.totalGamesPlayed == 1)
        #expect(stats.highestScore == game.players[0].score)
        let recent = try await api.recentGames(limit: 10, offset: 0)
        #expect(recent.games.first?.opponentLabel == "CPU (max-min)")
        #expect(recent.games.first?.result == (winner == registered.playerId ? "W" : winner.isEmpty ? "T" : "L"))
        let replay = try await api.replay(gameID: start.gameId)
        #expect(replay.turns.count == 36)
        #expect(replay.participants.map(\.participantType) == ["user", "cpu"])
    }

    @Test func cpuMoveHonoursTheRequestedHeuristic() async throws {
        // Blue threatens a 2×2 at (1,1); max-min blocks, random usually doesn't.
        var game = Game(boardSize: 8, players: [
            PlayerState(id: 1, name: "Blue", colorHex: "#0583D2"),
            PlayerState(id: 2, name: "CPU", colorHex: "#FF3131", isCPU: true, cpuLevel: .maxMin),
        ])
        for (r, c) in [(0, 0), (6, 6), (0, 1), (6, 3), (1, 0)] { try game.place(at: Cell(row: r, col: c)) }
        let reply = try await api().cpuMove(CPUMoveRequest(gameID: 1, game: game))
        #expect(reply.cell == Cell(row: 1, col: 1))
    }

    @Test func iosOAuthReturnsTheAppScheme() async throws {
        let api = api()
        let login = try await api.oauthLoginURL(.google, client: .ios)
        #expect(login.url.scheme == "squareoff")
        #expect(try await api.checkAuth())
    }
}
