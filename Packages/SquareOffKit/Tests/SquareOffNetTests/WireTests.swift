import Foundation
import Testing
import SquareOffCore
@testable import SquareOffNet

private func jsonObject(_ value: some Encodable) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

/// Client messages must carry exactly the keys `use-game-socket.ts` sends.
@Suite("WebSocket client messages")
struct ClientMessageTests {
    @Test func createRoom() throws {
        let seat = PlayerPayload.seat(id: 1, name: "Ian", colorHex: "#0583D2", playerID: "guest-1")
        let body = try jsonObject(ClientMessage.createRoom(player: seat, boardSize: 6, timer: 20, gameID: 42, roomCode: nil))
        #expect(Set(body.keys) == ["type", "player", "gameState", "timer", "gameId"])
        #expect(body["type"] as? String == "CREATE_ROOM")
        let state = try #require(body["gameState"] as? [String: Any])
        #expect(state["boardSize"] as? Int == 6)
        #expect((state["boardState"] as? [[Any]])?.count == 6)
        let player = try #require(body["player"] as? [String: Any])
        #expect(player["isCPU"] as? Bool == false)
        #expect(player["fillStyle"] as? String == "#0583D2")
        #expect(player["currentMultiplier"] as? Int == 1)
    }

    @Test func gameUpdateAndRejoin() throws {
        let update = try jsonObject(ClientMessage.gameUpdate(cell: Cell(row: 2, col: 5)))
        #expect((update["gameState"] as? [String: Any])?["rowIndex"] as? Int == 2)
        #expect((update["gameState"] as? [String: Any])?["colIndex"] as? Int == 5)
        let rejoin = try jsonObject(ClientMessage.rejoinRoom(roomCode: 123, playerID: 2, role: .guest))
        #expect(rejoin["playerId"] as? Int == 2)
        #expect(rejoin["role"] as? String == "guest")
        #expect(Set(try jsonObject(ClientMessage.turnComplete).keys) == ["type"])
    }
}

@Suite("WebSocket server messages")
struct ServerMessageTests {
    @Test func unknownTypesNeverThrow() throws {
        #expect(try ServerMessage.decode(#"{"type":"SOMETHING_NEW","x":1}"#) == .unknown(type: "SOMETHING_NEW"))
    }

    @Test func lenientIdsAndSimpleMessages() throws {
        #expect(try ServerMessage.decode(##"{"type":"PLAYER_SLOT_ASSIGNED","id":"3","color":"#50C878"}"##) == .playerSlotAssigned(id: 3, color: "#50C878"))
        #expect(try ServerMessage.decode(#"{"type":"GUEST_AWAY","playerId":2}"#) == .guestAway(playerId: 2))
        #expect(try ServerMessage.decode(#"{"type":"REJOIN_FAILED","reason":"room_not_found"}"#) == .rejoinFailed(reason: "room_not_found"))
        #expect(try ServerMessage.decode(#"{"type":"GAME_START","spectatorCount":1}"#) == .gameStart(spectatorCount: 1))
    }

    @Test func gameUpdateRoundTripsThroughTheRulesEngine() throws {
        var game = Game(boardSize: 6, players: [
            PlayerState(id: 1, name: "Host", colorHex: "#0583D2"),
            PlayerState(id: 3, name: "Guest", colorHex: "#50C878"),
        ])
        let seats = game.players.map { PlayerPayload.seat(id: $0.id, name: $0.name, colorHex: $0.colorHex, playerID: nil) }
        var last: MoveResult?
        for (r, c) in [(0, 0), (5, 5), (0, 1), (5, 4), (1, 0), (4, 5), (1, 1)] {
            last = try game.place(at: Cell(row: r, col: c))
        }
        let snapshot = GameSnapshotPayload(gameState: GameStatePayload(game: game, seats: seats, move: last), timer: 0, boardSize: 6)
        var envelope = try jsonObject(snapshot)
        envelope["type"] = "GAME_UPDATE"
        let data = try JSONSerialization.data(withJSONObject: envelope)
        guard case let .gameUpdate(decoded) = try ServerMessage.decode(data) else {
            Issue.record("not a GAME_UPDATE")
            return
        }
        #expect(decoded.gameState.moveCell == Cell(row: 1, col: 1))
        #expect(decoded.gameState.newShapes?.count == 1)
        #expect(decoded.gameState.players?.first?.currentScore == 4)
        #expect(decoded.gameState.players?.first?.scoreHistory?.count == 7)
        #expect(game.matches(decoded.gameState))

        let restored = try #require(Game(restoring: decoded, timerSeconds: 0))
        #expect(restored.players.map { $0.id } == [1, 3])
        #expect(restored.players[0].squares.count == 1)
        #expect(restored.currentPlayerIndex == 1)
        #expect(restored.matches(decoded.gameState))

        // Replaying the same cell on the pre-move game reproduces the server's state bit for bit.
        var replay = try #require(Game(restoring: GameSnapshotPayload(gameState: .empty(boardSize: 6, players: seats)), timerSeconds: 0))
        for (r, c) in [(0, 0), (5, 5), (0, 1), (5, 4), (1, 0), (4, 5), (1, 1)] { try replay.place(at: Cell(row: r, col: c)) }
        #expect(replay.matches(decoded.gameState))
        #expect(!replay.matches(GameStatePayload(game: game, seats: seats, move: nil).withScore(99)))
    }
}

private extension GameStatePayload {
    func withScore(_ score: Int) -> GameStatePayload {
        var copy = self
        copy.players?[0].currentScore = score
        return copy
    }
}
