import Foundation
import SquareOffCore

/// In-memory stand-in for the server, used by the contract tests and by any future flow that
/// records games through `SquareOffAPI`. The v1 app does not link this module: local games and
/// CPU moves run entirely on device via `SquareOffCore.CPUStrategy`.
/// `cpuMove` uses a simple greedy rule (best immediate score, else block, else random), which is
/// close to `max-min-optimal` but is NOT the server's algorithm.
public actor MockSquareOffAPI: SquareOffAPI {
    public static let guestIDs = [
        "00000000-0000-0000-0000-000000000001",
        "00000000-0000-0000-0000-000000000002",
        "00000000-0000-0000-0000-000000000003",
        "00000000-0000-0000-0000-000000000004",
    ]

    private var nextGameID = 1
    private var nextTurnID = 1
    private var loggedIn = false
    private let latency: Duration

    public init(latency: Duration = .milliseconds(150)) {
        self.latency = latency
    }

    public func guests() async throws -> GuestsResponse {
        try await Task.sleep(for: latency)
        return GuestsResponse(guests: Self.guestIDs)
    }

    public func cpuPlayer(_ level: CPULevel) async throws -> CPUPlayerResponse {
        try await Task.sleep(for: latency)
        return CPUPlayerResponse(
            id: level.number,
            cpuType: level.cpuType,
            displayName: "CPU (\(level.shortName))",
            color: "#FF3131"
        )
    }

    public func login(_ request: LoginRequest) async throws {
        try await Task.sleep(for: latency)
        guard !request.emailOrUsername.isEmpty, !request.password.isEmpty else {
            throw APIError.http(status: 401, body: #"{"detail":"Invalid credentials"}"#)
        }
        loggedIn = true
    }

    public func register(_ request: RegisterRequest) async throws {
        try await Task.sleep(for: latency)
    }

    public func logout() async throws {
        loggedIn = false
    }

    public func checkAuth() async throws -> Bool {
        loggedIn
    }

    public func startGame(_ request: StartGameRequest) async throws -> StartGameResponse {
        try await Task.sleep(for: latency)
        defer { nextGameID += 1 }
        let participants = request.players.enumerated().map { index, player in
            StartGameResponse.Participant(
                playerId: player.playerId ?? "\(player.id)",
                participantId: nextGameID * 10 + index
            )
        }
        return StartGameResponse(gameId: nextGameID, participants: participants)
    }

    public func insertTurn(gameID: Int, _ turn: GameTurnRequest) async throws -> GameTurnResponse {
        defer { nextTurnID += 1 }
        return GameTurnResponse(turnId: nextTurnID)
    }

    public func cpuMove(_ request: CPUMoveRequest) async throws -> CPUMoveResponse {
        let cell = Self.greedyMove(for: request)
        return CPUMoveResponse(row: cell.row, col: cell.col)
    }

    static func greedyMove(for request: CPUMoveRequest) -> Cell {
        let size = request.boardState.count
        var board = Board(size: size)
        for row in 0..<size {
            for col in 0..<size {
                board[row, col] = request.boardState[row][col]?.id
            }
        }
        let existing = Set(request.gamePlayers.flatMap { player in
            player.squares.map { "square-\($0.row)-\($0.col)-\($0.num)" }
                + player.diamonds.map { "diamond-\($0.row)-\($0.col)-\($0.num)" }
        })
        let me = request.currentPlayer.id
        let opponent = request.gamePlayers.first { $0.id != me }?.id ?? me

        func gain(_ cell: Cell, for seat: Int) -> Int {
            var copy = board
            copy[cell] = seat
            let shapes = copy.findNewSquares(excluding: existing) + copy.findNewDiamonds(excluding: existing)
            return shapes.filter { $0.ownerID == seat }.reduce(0) { $0 + $1.points }
        }

        let empty = board.emptyCells
        var best: [Cell] = []
        var bestScore = 0
        for cell in empty {
            let score = max(gain(cell, for: me), gain(cell, for: opponent))
            if score > bestScore {
                bestScore = score
                best = [cell]
            } else if score == bestScore, score > 0 {
                best.append(cell)
            }
        }
        return best.randomElement() ?? empty.randomElement() ?? Cell(row: 0, col: 0)
    }
}
