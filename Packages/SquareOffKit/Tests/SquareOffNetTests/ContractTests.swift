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
    @Test func createGuestCarriesTheSessionToken() throws {
        let response = try JSONDecoder().decode(CreateGuestResponse.self, from: fixture("create_guest_response"))
        #expect(response.playerId.count == 36)
        #expect(response.accessToken?.hasPrefix("eyJ") == true && response.tokenType == "bearer")
        // Pre-2026-11 servers answered without a token; the fields stay optional for them.
        let old = try JSONDecoder().decode(CreateGuestResponse.self, from: Data(#"{"message":"Guest created successfully","player_id":"abc"}"#.utf8))
        #expect(old.accessToken == nil)
    }

    @Test func newCPUDefinitionsAndSignUpResponses() throws {
        for (name, type) in [("cpu_player_max_min_plus", "max-min-plus"), ("cpu_player_grandmaster", "grandmaster"), ("cpu_player_impossible", "impossible")] {
            let cpu = try JSONDecoder().decode(CPUPlayerResponse.self, from: fixture(name))
            #expect(cpu.cpuType == type)
        }
        let registered = try JSONDecoder().decode(RegisterResponse.self, from: fixture("register_response"))
        #expect(registered.verificationRequired && registered.playerId.count == 36)
        #expect(try JSONDecoder().decode(MessageResponse.self, from: fixture("verify_email_resend_response")).message.hasPrefix("If that address"))
        let verified = try JSONDecoder().decode(VerifyEmailResponse.self, from: Data(#"{"message":"Email verified","already_verified":false}"#.utf8))
        #expect(!verified.alreadyVerified)
    }

    @Test func sessionErrorBodies() throws {
        func error(_ name: String, status: Int) throws -> APIError {
            .http(status: status, body: String(decoding: try fixture(name), as: UTF8.self))
        }
        #expect(try error("error_session_required", status: 401).isSessionRequired)
        #expect(try error("error_account_required", status: 401).isAccountRequired)
        #expect(try error("error_already_signed_in", status: 409).detail == APIError.alreadySignedInCode)
        #expect(try error("error_seat_not_yours", status: 403).detail == "seat_not_yours")
        #expect(try error("error_not_a_player", status: 403).detail == "not_a_player")
        #expect(try error("error_email_unverified", status: 403).detail == "email_unverified")
        #expect(try error("error_verify_token_invalid", status: 400).detail == "verify_token_invalid")
        #expect(try error("error_session_required", status: 401).sessionEndReason == nil, "not a sign-out")
    }

    @Test func cpuPlayer() throws {
        let response = try JSONDecoder().decode(CPUPlayerResponse.self, from: fixture("cpu_player_max_min"))
        #expect(response.cpuType == "max-min")
        #expect(response.displayName == "CPU (Max-Min)")
    }

    @Test func startGame() throws {
        let response = try JSONDecoder().decode(StartGameResponse.self, from: fixture("start_game_response"))
        #expect(response.gameId > 0)
        #expect(response.participants.map(\.slot) == [0, 1])
        #expect(response.participants[1].playerId.allSatisfy(\.isNumber), "the CPU seat echoes the definition id")
        // Pass & Play: the caller's seat plus two id-less seats, each given a minted guest.
        let seats = try JSONDecoder().decode(StartGameResponse.self, from: fixture("start_game_pass_and_play"))
        #expect(seats.participants.map(\.slot) == [0, 1, 2])
        #expect(Set(seats.participants.map(\.playerId)).count == 3)
        #expect(seats.participants.allSatisfy { $0.playerId.count == 36 })
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

    @Test func feedbackPasswordAndDeletionKeys() throws {
        let feedback = try jsonObject(FeedbackRequest(subject: "Hi", message: "There"))
        #expect(Set(feedback.keys) == ["subject", "message", "contact_email", "display_name"])
        #expect(feedback["contact_email"] is NSNull)   // explicit null, like the web
        #expect(Set(try jsonObject(PasswordResetRequest(token: "t", newPassword: "p")).keys) == ["token", "new_password"])
        #expect(Set(try jsonObject(PasswordForgotRequest(email: "a@b.c")).keys) == ["email"])
        #expect(try jsonObject(AccountDeleteRequest()).isEmpty)
        #expect(try jsonObject(AccountDeleteRequest(appleAuthorizationCode: "c"))["apple_authorization_code"] as? String == "c")
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
        let api = MockSquareOffAPI(latency: .zero)
        _ = try await api.createGuest(CreateGuestRequest(name: "Guest", color: "#0583D2"))   // /cpu_move needs a session
        let move = try await api.cpuMove(CPUMoveRequest(gameID: 1, game: game))
        #expect(move.cell == Cell(row: 6, col: 6))
    }
}

/// A token holder the live tests fill after `create_guest`, standing in for the app's Keychain.
final class LiveTokenBox: TokenProvider, @unchecked Sendable {
    var token: String?
    func accessToken() -> String? { token }
    func kind(of token: String) -> TokenKind { .guest }
}

/// Opt-in: runs the real web flow against the local server.
/// `docker compose up -d db backend` in square-off-react/square-off-app, then
/// `SQUAREOFF_LIVE_API=1 swift test --filter LiveContract`.
@Suite("Live contract (local server)", .enabled(if: ProcessInfo.processInfo.environment["SQUAREOFF_LIVE_API"] == "1"))
struct LiveContractTests {
    let box = LiveTokenBox()
    var api: LiveSquareOffAPI { LiveSquareOffAPI(environment: .local, tokenProvider: box) }

    /// `POST /create_guest` as the app does it on launch: the token goes in the box, the id is the seat.
    private func mintGuest() async throws -> String {
        let guest = try await api.createGuest(CreateGuestRequest(name: "Guest", color: "#0583D2"))
        box.token = try #require(guest.accessToken)
        return guest.playerId
    }

    @Test func guestCPUGameFlowMatchesWeb() async throws {
        let guestID = try await mintGuest()
        let cpu = try await api.cpuPlayer(.maxMin)
        var game = Game(boardSize: 8, players: [
            PlayerState(id: 1, name: "Player 1", colorHex: "#0583D2", serverPlayerID: guestID),
            PlayerState(id: 2, name: "CPU (max-min)", colorHex: cpu.color ?? "#FF3131", isCPU: true, cpuLevel: .maxMin, serverPlayerID: String(cpu.id)),
        ])

        let start = try await api.startGame(StartGameRequest(boardSize: 8, timer: 0, players: game.players, type: .local))
        #expect(start.participants.count == 2)
        #expect(start.participants.map(\.slot) == [0, 1])
        #expect(start.participants[0].playerId == guestID)
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

    @Test func guestSessionIsRequiredRenewedAndNotAnAccount() async throws {
        box.token = nil
        await #expect(throws: APIError.self) { _ = try await api.cpuPlayer(.random) }   // 401 session_required
        let guestID = try await mintGuest()
        let renewed = try await api.createGuest(CreateGuestRequest(name: "Guest", color: "#0583D2"))
        #expect(renewed.playerId == guestID, "a live guest token renews the same session")
        #expect(try await api.checkAuth() == false, "a guest is not an account (401 account_required)")
    }

    @Test func startRefusesSomebodyElsesSeatAndMintsIdLessOnes() async throws {
        _ = try await mintGuest()
        let foreign = StartPlayer(id: 1, name: "Not me", color: "#0583D2", playerId: UUID().uuidString.lowercased(), isCPU: false, cpuType: nil)
        let cpu = StartPlayer(id: 2, name: "CPU", color: "#FF3131", playerId: "1", isCPU: true, cpuType: "random")
        await #expect(throws: APIError.self) {
            _ = try await api.startGame(StartGameRequest(boardSize: 6, timer: 0, seats: [foreign, cpu], type: .local))
        }
        let seats = [
            StartPlayer(id: 1, name: "Player 1", color: "#0583D2", playerId: nil, isCPU: false, cpuType: nil),
            StartPlayer(id: 2, name: "Player 2", color: "#FF3131", playerId: nil, isCPU: false, cpuType: nil),
            StartPlayer(id: 3, name: "Player 3", color: "#50C878", playerId: nil, isCPU: false, cpuType: nil),
        ]
        let start = try await api.startGame(StartGameRequest(boardSize: 6, timer: 0, seats: seats, type: .local))
        #expect(start.participants.map(\.slot) == [0, 1, 2])
        #expect(Set(start.participants.map(\.playerId)).count == 3, "every id-less seat got its own guest")
    }

    @Test func cnnMovePlaysLegallyOn8x8() async throws {
        var game = Game(boardSize: 8, players: [
            PlayerState(id: 1, name: "Player 1", colorHex: "#0583D2"),
            PlayerState(id: 2, name: "CPU (cnn)", colorHex: "#FF3131", isCPU: true, cpuLevel: .cnn),
        ])
        try game.place(at: Cell(row: 0, col: 0))
        let reply = try await api.cpuMove(CPUMoveRequest(gameID: 1, game: game))
        #expect(game.board[reply.cell] == nil)
    }

    /// The Keras model is hard-coded to 8×8; the app only offers Level 3 on 8×8 boards.
    @Test func cnnRejectsOtherBoardSizes() async throws {
        var game = Game(boardSize: 6, players: [
            PlayerState(id: 1, name: "Player 1", colorHex: "#0583D2"),
            PlayerState(id: 2, name: "CPU (cnn)", colorHex: "#FF3131", isCPU: true, cpuLevel: .cnn),
        ])
        try game.place(at: Cell(row: 0, col: 0))
        await #expect(throws: APIError.self) {
            _ = try await api.cpuMove(CPUMoveRequest(gameID: 1, game: game))
        }
    }
}
