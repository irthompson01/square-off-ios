import SquareOffCore

// Bridges the server's snapshot format and the rules engine.
//
// Online games apply each echoed move locally with `Game.place(at:)` (keeps spins, sounds and
// the move history) and verify with `matches(_:)`; when the two disagree the client rebuilds
// from the snapshot with `Game(restoring:timerSeconds:)`. The mock room server uses
// `GameStatePayload(game:seats:move:)` to serialise exactly like `Game.to_state()`.

extension Game {
    /// Full rebuild from a `GAME_STATE` / `GAME_UPDATE` snapshot. `nil` when the snapshot can't
    /// describe a game (fewer than two seats, a ragged board, bad ids).
    public init?(restoring snapshot: GameSnapshotPayload, timerSeconds: Int) {
        let state = snapshot.gameState
        let seats = snapshot.seats
        guard (2...4).contains(seats.count),
              Set(seats.map(\.id)).count == seats.count,
              seats.allSatisfy({ (1...4).contains($0.id) })
        else { return nil }
        let size = state.boardState.count
        guard size >= 2, state.boardState.allSatisfy({ $0.count == size }) else { return nil }

        var board = Board(size: size)
        for row in 0..<size {
            for col in 0..<size {
                board[row, col] = state.boardState[row][col]?.id
            }
        }
        let shapes = state.allShapes
        let players = seats.map { seat -> PlayerState in
            var player = PlayerState(
                id: seat.id,
                name: seat.displayName,
                colorHex: seat.colorHex,
                isCPU: seat.isCPU ?? false,
                cpuLevel: seat.cpuType.flatMap(CPULevel.init(rawValue:)),
                serverPlayerID: seat.playerId,
                participantID: seat.participantId
            )
            player.score = seat.currentScore ?? 0
            player.multiplier = seat.currentMultiplier ?? 1
            player.scoreHistory = seat.scoreHistory ?? []
            player.squares = shapes.filter { $0.ownerID == seat.id && $0.kind == .square }
            player.diamonds = shapes.filter { $0.ownerID == seat.id && $0.kind == .diamond }
            return player
        }
        let index = state.currentPlayerIndex ?? snapshot.currentPlayerIndex ?? 0
        guard players.indices.contains(index) else { return nil }
        self.init(board: board, players: players, currentPlayerIndex: index, timerSeconds: timerSeconds)
    }

    /// True when the board, the turn index and every seat's score and multiplier agree with `state`.
    public func matches(_ state: GameStatePayload) -> Bool {
        guard state.boardState.count == board.size else { return false }
        for row in 0..<board.size {
            guard state.boardState[row].count == board.size else { return false }
            for col in 0..<board.size where state.boardState[row][col]?.id != board[row, col] {
                return false
            }
        }
        if let index = state.currentPlayerIndex, index != currentPlayerIndex { return false }
        for seat in state.players ?? [] {
            guard let mine = players.first(where: { $0.id == seat.id }) else { return false }
            if let score = seat.currentScore, score != mine.score { return false }
            if let multiplier = seat.currentMultiplier, multiplier != mine.multiplier { return false }
        }
        return true
    }
}

extension GameStatePayload {
    /// Serialises like the server (`Game.to_state()` + the `make_move` extras when `move` is given).
    public init(game: Game, seats: [PlayerPayload], move: MoveResult?) {
        let size = game.board.size
        let board: [[BoardCellPayload?]] = (0..<size).map { row in
            (0..<size).map { col in game.board[row, col].map(BoardCellPayload.init(id:)) }
        }
        let players: [PlayerPayload] = seats.map { seat in
            var out = seat
            if let live = game.players.first(where: { $0.id == seat.id }) {
                out.currentScore = live.score
                out.currentMultiplier = live.multiplier
                out.scoreHistory = live.scoreHistory
                let mine = move?.playerID == seat.id
                out.multiplierIncrease = mine ? move?.multiplierIncrease : 0
                out.scoreIncrease = mine ? move?.scoreIncrease : 0
                out.newSquareCount = mine ? move?.newSquares.count : 0
                out.newDiamondCount = mine ? move?.newDiamonds.count : 0
            }
            return out
        }
        self.init(
            boardState: board,
            players: players,
            currentPlayerIndex: game.currentPlayerIndex,
            gameOver: game.isOver,
            squares: game.players.flatMap(\.squares).map(ShapePayload.init),
            diamonds: game.players.flatMap(\.diamonds).map(ShapePayload.init),
            rowIndex: move?.cell.row,
            colIndex: move?.cell.col,
            scoreIncrease: move?.scoreIncrease,
            multiplierIncrease: move?.multiplierIncrease,
            newShapes: move.map {
                NewShapesPayload(squares: $0.newSquares.map(ShapePayload.init),
                                 diamonds: $0.newDiamonds.map(ShapePayload.init),
                                 count: $0.newShapeCount)
            }
        )
    }
}
