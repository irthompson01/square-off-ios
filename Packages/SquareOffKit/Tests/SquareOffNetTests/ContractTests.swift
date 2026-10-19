import Foundation
import Testing
import SquareOffCore
@testable import SquareOffNet

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private func jsonObject(_ value: some Encodable) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func cpuGame() -> Game {
    Game(boardSize: 8, players: [
        PlayerState(id: 1, name: "Player 1", colorHex: "#0583D2", serverPlayerID: "guest-uuid", participantID: 10),
        PlayerState(id: 2, name: "CPU (max-min)", colorHex: "#FF3131", isCPU: true, cpuLevel: .maxMin, serverPlayerID: "2", participantID: 11),
    ])
}

/// Responses captured from the local docker-compose server (`https://localhost:8002/api`).
@Suite("Decoding real server responses")
struct DecodingTests {
    @Test func guests() throws {
        let response = try JSONDecoder().decode(GuestsResponse.self, from: fixture("guests"))
        #expect(response.guests.count == 4)
    }

    @Test func cpuPlayer() throws {
        let response = try JSONDecoder().decode(CPUPlayerResponse.self, from: fixture("cpu_player_max_min"))
        #expect(response.cpuType == "max-min")
        #expect(response.displayName == "CPU (Max-Min)")
    }

    @Test func startGame() throws {
        let response = try JSONDecoder().decode(StartGameResponse.self, from: fixture("start_game_response"))
        #expect(response.gameId == 2535)
        #expect(response.participants.map(\.participantId) == [4677, 4678])
    }

    @Test func cpuMoveIgnoresExtraDebugFields() throws {
        let response = try JSONDecoder().decode(CPUMoveResponse.self, from: fixture("cpu_move_response"))
        #expect(response.cell == Cell(row: 4, col: 4))
    }

    @Test func gameTurn() throws {
        let response = try JSONDecoder().decode(GameTurnResponse.self, from: fixture("game_turn_response"))
        #expect(response.turnId == 56100)
    }
}

/// Request bodies must use the same keys the web client sends.
@Suite("Request bodies match the web client")
struct EncodingTests {
    @Test func startGameKeys() throws {
        let game = cpuGame()
        let body = try jsonObject(StartGameRequest(boardSize: 8, timer: 20, players: game.players, type: .local))
        #expect(Set(body.keys) == ["board_size", "timer", "players", "type", "is_cpu", "cpu_type"])
        #expect(body["is_cpu"] as? Bool == true)
        #expect(body["cpu_type"] as? String == "max-min")
        let seat = try #require((body["players"] as? [[String: Any]])?.last)
        #expect(Set(seat.keys) == ["id", "name", "color", "playerId", "isCPU", "cpuType"])
    }

    @Test func gameTurnKeys() throws {
        var game = cpuGame()
        let move = try game.place(at: Cell(row: 1, col: 4))
        let body = try jsonObject(GameTurnRequest(move: move, player: game.players[0]))
        #expect(Set(body.keys) == [
            "row_index", "col_index", "player_id", "current_score", "current_multiplier",
            "multiplier_increase", "score_increase", "new_diamond_count", "new_square_count",
            "is_cpu", "cpu_type", "participant_id",
        ])
        #expect(body["participant_id"] as? Int == 10)
    }

    @Test func cpuMoveSendsBoardAndExistingShapes() throws {
        var game = cpuGame()
        for (r, c) in [(0, 0), (5, 5), (0, 1), (5, 7), (1, 0), (7, 5), (1, 1)] {
            try game.place(at: Cell(row: r, col: c))
        }
        let body = try jsonObject(CPUMoveRequest(gameID: 7, game: game))
        #expect(Set(body.keys) == ["game_id", "board_state", "current_player", "game_players", "cpu_type"])
        let board = try #require(body["board_state"] as? [[Any]])
        #expect(board.count == 8)
        #expect((board[0][0] as? [String: Any])?["id"] as? Int == 1)
        #expect(board[3][3] is NSNull)
        let blue = try #require((body["game_players"] as? [[String: Any]])?.first)
        let squares = try #require(blue["squares"] as? [[String: Any]])
        #expect(squares.first?["size"] as? Int == 2)
    }
}

@Suite("Mock API")
struct MockAPITests {
    @Test func mockCPUTakesAnOpenSquare() async throws {
        var game = cpuGame()
        // Red (CPU) owns three corners of a 2×2; blue's last move leaves (6,6) open.
        for (r, c) in [(0, 0), (5, 5), (2, 2), (5, 6), (3, 7)] {
            try game.place(at: Cell(row: r, col: c))
        }
        try game.place(at: Cell(row: 6, col: 5)) // red
        try game.place(at: Cell(row: 0, col: 7)) // blue
        let move = try await MockSquareOffAPI(latency: .zero).cpuMove(CPUMoveRequest(gameID: 1, game: game))
        #expect(move.cell == Cell(row: 6, col: 6))
    }
}

/// Opt-in: runs the real web flow against the local server.
/// `docker compose up -d db backend` in square-off-react/square-off-app, then
/// `SQUAREOFF_LIVE_API=1 swift test --filter LiveContract`.
@Suite("Live contract (local server)", .enabled(if: ProcessInfo.processInfo.environment["SQUAREOFF_LIVE_API"] == "1"))
struct LiveContractTests {
    let api = LiveSquareOffAPI(environment: .local)

    @Test func guestCPUGameFlowMatchesWeb() async throws {
        let guests = try await api.guests()
        let cpu = try await api.cpuPlayer(.maxMin)
        var game = Game(boardSize: 8, players: [
            PlayerState(id: 1, name: "Player 1", colorHex: "#0583D2", serverPlayerID: try #require(guests.guests.first)),
            PlayerState(id: 2, name: "CPU (max-min)", colorHex: cpu.color ?? "#FF3131", isCPU: true, cpuLevel: .maxMin, serverPlayerID: String(cpu.id)),
        ])

        let start = try await api.startGame(StartGameRequest(boardSize: 8, timer: 0, players: game.players, type: .local))
        #expect(start.participants.count == 2)
        game.assignParticipants(Dictionary(uniqueKeysWithValues: zip([1, 2], start.participants.map(\.participantId))))

        // Blue threatens a 2×2; Max-Min must block at (1,1).
        for (r, c) in [(0, 0), (6, 6), (0, 1), (6, 3), (1, 0)] {
            let move = try game.place(at: Cell(row: r, col: c))
            let mover = try #require(game.players.first { $0.id == move.playerID })
            _ = try await api.insertTurn(gameID: start.gameId, GameTurnRequest(move: move, player: mover))
        }
        let reply = try await api.cpuMove(CPUMoveRequest(gameID: start.gameId, game: game))
        #expect(reply.cell == Cell(row: 1, col: 1))
    }

    @Test func guestIsNotAuthenticated() async throws {
        #expect(try await api.checkAuth() == false)
    }

    @Test func cnnLevelIsBrokenOnServer() async throws {
        let game = Game(boardSize: 8, players: [
            PlayerState(id: 1, name: "Player 1", colorHex: "#0583D2"),
            PlayerState(id: 2, name: "CPU (cnn)", colorHex: "#FF3131", isCPU: true, cpuLevel: .cnn),
        ])
        var rotated = game
        try rotated.place(at: Cell(row: 0, col: 0))
        // Known server bug: CNN_MODEL load is commented out in routes/model.py → 500.
        await withKnownIssue("CNN model not loaded on the server") {
            _ = try await api.cpuMove(CPUMoveRequest(gameID: 1, game: rotated))
        }
    }
}
