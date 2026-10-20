public struct PlayerState: Hashable, Sendable, Identifiable {
    /// Seat number (1...4). Matches the web's `Player.id` and the `id` written into board cells.
    public let id: Int
    public var name: String
    public var colorHex: String
    public var isCPU: Bool
    public var cpuLevel: CPULevel?
    /// Server UUID (logged-in user, seeded guest or CPU definition id). Sent as `playerId`.
    public var serverPlayerID: String?
    public var participantID: Int?

    public var score = 0
    public var multiplier = 1
    public var squares: [BoardShape] = []
    public var diamonds: [BoardShape] = []
    /// Score after each of this player's completed moves, for the end-game chart.
    public var scoreHistory: [Int] = []

    public var shapeCount: Int { squares.count + diamonds.count }

    public init(
        id: Int,
        name: String,
        colorHex: String,
        isCPU: Bool = false,
        cpuLevel: CPULevel? = nil,
        serverPlayerID: String? = nil,
        participantID: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.isCPU = isCPU
        self.cpuLevel = cpuLevel
        self.serverPlayerID = serverPlayerID
        self.participantID = participantID
    }
}

/// Everything a UI or the server needs about one move. Field names follow the web's
/// `computeLocalMoveResult` + `GameTurn` payload.
public struct MoveResult: Hashable, Sendable {
    public let cell: Cell
    public let playerID: Int
    public let newSquares: [BoardShape]
    public let newDiamonds: [BoardShape]
    public let scoreIncrease: Int
    public let multiplierIncrease: Int
    public let scoreAfter: Int
    public let multiplierAfter: Int

    public var newShapes: [BoardShape] { newSquares + newDiamonds }
    public var newShapeCount: Int { newShapes.count }

    /// Turns each tile spins, per the web's `triggerShapeFlips`: corners of every new shape spin
    /// `2 × newShapeCount` turns (accumulating when a tile is a corner of several shapes).
    /// With no new shape, the placed tile spins once.
    public var spinTurns: [Cell: Int] {
        guard newShapeCount > 0 else { return [cell: 1] }
        var turns: [Cell: Int] = [:]
        for shape in newShapes {
            for corner in shape.corners {
                turns[corner, default: 0] += 2 * newShapeCount
            }
        }
        return turns
    }
}

/// The outcome of a hypothetical placement: what `Game.place(at:)` would add to the mover.
public struct PlacementPreview: Hashable, Sendable {
    public let newSquares: [BoardShape]
    public let newDiamonds: [BoardShape]
    /// Points gained, with the multiplier already applied (Python `calculate_score()[1]`).
    public let scoreIncrease: Int
    /// The mover's multiplier after the move (Python `calculate_score()[2]`).
    public let multiplierAfter: Int
    public let multiplierIncrease: Int

    public var newShapeCount: Int { newSquares.count + newDiamonds.count }
}

public enum MoveError: Error, Equatable {
    case gameOver
    case outOfBounds
    case occupied
}

/// Local game state machine. Port of `applyLocalPlacementAndScoring` + `computeLocalMoveResult`.
public struct Game: Hashable, Sendable {
    public private(set) var board: Board
    public private(set) var players: [PlayerState]
    public private(set) var currentPlayerIndex = 0
    public private(set) var moves: [MoveResult] = []
    public let timerSeconds: Int

    public init(boardSize: Int, players: [PlayerState], timerSeconds: Int = 0) {
        self.init(board: Board(size: boardSize), players: players, currentPlayerIndex: 0, timerSeconds: timerSeconds)
    }

    /// Restores a game from an existing position (saved games, replays, CPU test fixtures).
    /// Python's `Game.from_state` equivalent. Seats must be numbered 1…n in order so that
    /// "next player" is `players[(index + 1) % n]`, exactly like the server's `players[id % n]`.
    public init(board: Board, players: [PlayerState], currentPlayerIndex: Int = 0, timerSeconds: Int = 0) {
        precondition((2...4).contains(players.count), "Square Off supports 2–4 players")
        precondition(players.map(\.id) == Array(1...players.count), "Seats must be numbered 1…n in order")
        precondition(players.indices.contains(currentPlayerIndex), "currentPlayerIndex out of range")
        self.board = board
        self.players = players
        self.currentPlayerIndex = currentPlayerIndex
        self.timerSeconds = timerSeconds
    }

    public var currentPlayer: PlayerState { players[currentPlayerIndex] }
    public var isOver: Bool { board.isFull }
    public var allShapes: [BoardShape] { players.flatMap { $0.squares + $0.diamonds } }

    /// Final standings: score, then total shapes, then diamonds (`game-end-ranking.ts`).
    public var standings: [PlayerState] {
        players.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.shapeCount != b.shapeCount { return a.shapeCount > b.shapeCount }
            return a.diamonds.count > b.diamonds.count
        }
    }

    /// True when first and second are still tied after all tie-breakers.
    public var isDraw: Bool {
        let s = standings
        guard s.count >= 2 else { return false }
        return s[0].score == s[1].score
            && s[0].shapeCount == s[1].shapeCount
            && s[0].diamonds.count == s[1].diamonds.count
    }

    @discardableResult
    public mutating func place(at cell: Cell) throws -> MoveResult {
        guard !isOver else { throw MoveError.gameOver }
        guard (0..<board.size).contains(cell.row), (0..<board.size).contains(cell.col) else {
            throw MoveError.outOfBounds
        }
        guard board[cell] == nil else { throw MoveError.occupied }

        let index = currentPlayerIndex
        let mover = players[index]
        let preview = preview(placing: cell, byPlayerAt: index)

        board[cell] = mover.id
        var updated = mover
        updated.squares += preview.newSquares
        updated.diamonds += preview.newDiamonds
        updated.multiplier = preview.multiplierAfter
        updated.score += preview.scoreIncrease

        players[index] = updated
        for i in players.indices {
            players[i].scoreHistory.append(players[i].score)
        }

        let result = MoveResult(
            cell: cell,
            playerID: mover.id,
            newSquares: preview.newSquares,
            newDiamonds: preview.newDiamonds,
            scoreIncrease: preview.scoreIncrease,
            multiplierIncrease: preview.multiplierIncrease,
            scoreAfter: updated.score,
            multiplierAfter: updated.multiplier
        )
        moves.append(result)
        currentPlayerIndex = (currentPlayerIndex + 1) % players.count
        return result
    }

    // MARK: Preview

    /// What `place(at:)` would score if `players[index]` put a tile on `cell`, without mutating.
    /// Precondition: `cell` is in bounds and empty.
    public func preview(placing cell: Cell, byPlayerAt index: Int) -> PlacementPreview {
        preview(placing: cell, byPlayerAt: index, existing: Set(allShapes.map(\.dedupeKey)))
    }

    /// Same as above with the dedupe set precomputed (the CPU evaluator calls this 2×N times per turn).
    func preview(placing cell: Cell, byPlayerAt index: Int, existing: Set<String>) -> PlacementPreview {
        let mover = players[index]
        var simulated = board
        simulated[cell] = mover.id

        // Only the mover can complete a shape with their own tile, so filter to the mover
        // exactly as the web does (`s.occupantId === player.id`).
        let newSquares = simulated.findNewSquares(excluding: existing).filter { $0.ownerID == mover.id }
        let newDiamonds = simulated.findNewDiamonds(excluding: existing).filter { $0.ownerID == mover.id }
        let newCount = newSquares.count + newDiamonds.count
        let points = (newSquares + newDiamonds).reduce(0) { $0 + $1.points }

        // Same rule as the web's `computeLocalMoveResult` and the server's `calculate_score`:
        // 0 shapes → ×1, +0; 1 shape → ×1, +points; n ≥ 2 → multiplier + n − 1, × that.
        switch newCount {
        case 0:
            return PlacementPreview(newSquares: [], newDiamonds: [], scoreIncrease: 0, multiplierAfter: 1, multiplierIncrease: 0)
        case 1:
            return PlacementPreview(newSquares: newSquares, newDiamonds: newDiamonds, scoreIncrease: points, multiplierAfter: 1, multiplierIncrease: 0)
        default:
            // Rulebook: new multiplier = current + shapes − 1 (from ×1 that is just `shapes`).
            let multiplier = mover.multiplier > 1 ? mover.multiplier + newCount - 1 : newCount
            return PlacementPreview(
                newSquares: newSquares,
                newDiamonds: newDiamonds,
                scoreIncrease: points * multiplier,
                multiplierAfter: multiplier,
                multiplierIncrease: newCount - 1
            )
        }
    }

    /// Writes server ids returned by `POST /start` back onto the seats.
    public mutating func assignParticipants(_ ids: [Int: Int]) {
        for i in players.indices {
            if let participant = ids[players[i].id] { players[i].participantID = participant }
        }
    }
}
