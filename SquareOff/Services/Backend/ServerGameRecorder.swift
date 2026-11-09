import Foundation
import SquareOffCore
import SquareOffNet

/// Records a local game the way the web client does: `POST /start` when it begins, one
/// `POST /{id}/turns` per move, `PUT /end` when the board is full. The session serialises the
/// calls, so this actor only has to keep the seat → server id map. The first failure disables
/// recording for the rest of the game and posts a single notice; play is never blocked.
///
/// Seats follow the server's claim rule: the caller's seat (seat 1) carries the signed-in
/// user's id or the device's guest id, every other human seat is sent without an id and the
/// server mints a guest for it. The ids it returns (matched by `slot`) are what turns and the
/// final scores are recorded under.
actor ServerGameRecorder: GameRecorder {
    static let offlineNotice = "Playing offline, this game won't be saved"

    private let api: any SquareOffAPI
    private let humanPlayerID: String?
    private let ensureGuest: @Sendable () async throws -> String
    private let notices: SessionNoticeRelay

    private var gameID: Int?
    private var playerIDs: [Int: String] = [:]
    private var participantIDs: [Int: Int] = [:]
    private var disabled = false

    init(api: any SquareOffAPI, humanPlayerID: String?, ensureGuest: @escaping @Sendable () async throws -> String,
         notices: SessionNoticeRelay) {
        self.api = api
        self.humanPlayerID = humanPlayerID
        self.ensureGuest = ensureGuest
        self.notices = notices
    }

    var recordedGameID: Int? { gameID }

    func gameStarted(_ game: Game, config: GameConfig) async {
        gameID = nil
        playerIDs = [:]
        participantIDs = [:]
        disabled = false
        do {
            var seats: [StartPlayer] = []
            for player in game.players {
                let id: String?
                if player.isCPU {
                    id = String(try await api.cpuPlayer(player.cpuLevel ?? .random).id)
                } else if player.id == 1 {
                    if let humanPlayerID { id = humanPlayerID } else { id = try await ensureGuest() }
                } else {
                    id = nil   // Pass & Play partners: the server mints a guest per seat
                }
                playerIDs[player.id] = id
                seats.append(StartPlayer(seat: player, playerID: id))
            }
            let response = try await api.startGame(StartGameRequest(boardSize: game.board.size, timer: game.timerSeconds, seats: seats, type: .local))
            gameID = response.gameId
            for (index, player) in game.players.enumerated() {
                let match = response.participants.first { $0.slot == index }
                    ?? response.participants.first { $0.slot == nil && $0.playerId == playerIDs[player.id] }
                    ?? (response.participants.indices.contains(index) ? response.participants[index] : nil)
                participantIDs[player.id] = match?.participantId
                if !player.isCPU, let id = match?.playerId, !id.isEmpty { playerIDs[player.id] = id }
            }
        } catch {
            await fail(error)
        }
    }

    func record(_ move: MoveResult, by player: PlayerState) async {
        guard !disabled, let gameID else { return }
        do {
            _ = try await api.insertTurn(gameID: gameID, GameTurnRequest(
                move: move, player: player, playerID: playerIDs[player.id], participantID: participantIDs[player.id]))
        } catch {
            await fail(error)
        }
    }

    func gameEnded(_ game: Game) async {
        guard !disabled, let gameID else { return }
        let winner = game.isDraw ? "" : (game.standings.first.flatMap { playerIDs[$0.id] } ?? "")
        let scores = game.players.map { ScoreEntry(playerId: playerIDs[$0.id] ?? String($0.id), score: $0.score) }
        do {
            try await api.endGame(GameEndRequest(gameId: gameID, winnerId: winner, scores: scores))
        } catch {
            await fail(error)
        }
    }

    private func fail(_ error: Error) async {
        guard !disabled else { return }
        disabled = true
        #if DEBUG
        print("[ServerGameRecorder] recording disabled: \((error as? APIError)?.detail ?? "\(error)")")
        #endif
        await notices.post(Self.offlineNotice)
    }
}
