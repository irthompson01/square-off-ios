import Foundation
import SquareOffCore
import SquareOffNet

/// Records a local game the way the web client does: `POST /start` when it begins, one
/// `POST /{id}/turns` per move, `PUT /end` when the board is full. The session serialises the
/// calls, so this actor only has to keep the seat → server id map. The first failure disables
/// recording for the rest of the game and posts a single notice; play is never blocked.
actor ServerGameRecorder: GameRecorder {
    static let offlineNotice = "Playing offline, this game won't be saved"

    private let api: any SquareOffAPI
    private let humanPlayerID: String?
    private let ensureGuest: @Sendable () async throws -> String
    private let localSeatIDs: [String]
    private let notices: SessionNoticeRelay

    private var gameID: Int?
    private var playerIDs: [Int: String] = [:]
    private var participantIDs: [Int: Int] = [:]
    private var disabled = false

    init(api: any SquareOffAPI, humanPlayerID: String?, ensureGuest: @escaping @Sendable () async throws -> String,
         localSeatIDs: [String], notices: SessionNoticeRelay) {
        self.api = api
        self.humanPlayerID = humanPlayerID
        self.ensureGuest = ensureGuest
        self.localSeatIDs = localSeatIDs
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
                    id = localSeatIDs.indices.contains(player.id - 2) ? localSeatIDs[player.id - 2] : nil
                }
                playerIDs[player.id] = id
                seats.append(StartPlayer(seat: player, playerID: id))
            }
            let response = try await api.startGame(StartGameRequest(boardSize: game.board.size, timer: game.timerSeconds, seats: seats, type: .local))
            gameID = response.gameId
            for (index, player) in game.players.enumerated() {
                let match = response.participants.first { $0.playerId == playerIDs[player.id] }
                    ?? (response.participants.indices.contains(index) ? response.participants[index] : nil)
                participantIDs[player.id] = match?.participantId
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
        print("[ServerGameRecorder] recording disabled: \(error)")
        #endif
        await notices.post(Self.offlineNotice)
    }
}
