/// One-ply evaluation of a candidate cell, as every server heuristic computes it
/// (`routes/model.py`): place the tile for the mover and, separately, for the next seat,
/// then score each with that player's current multiplier.
public struct MoveEvaluation: Hashable, Sendable {
    public let cell: Cell
    /// Mover's `score_increase` for this cell.
    public let ownGain: Int
    /// Mover's multiplier after this cell (Max-Random's tie-break).
    public let ownMultiplierAfter: Int
    /// `score_increase` if the NEXT seat took this cell instead. The Max-Min family only ever
    /// looks at the next player, even in 3–4 player games.
    public let opponentGain: Int
}

public enum MoveEvaluator {
    /// Evaluates every empty cell in row-major order, matching `calculate_available_moves`.
    public static func evaluate(_ game: Game) -> [MoveEvaluation] {
        let me = game.currentPlayerIndex
        let opponent = (me + 1) % game.players.count
        let existing = Set(game.allShapes.map(\.dedupeKey))
        return game.board.emptyCells.map { cell in
            let own = game.preview(placing: cell, byPlayerAt: me, existing: existing)
            let theirs = game.preview(placing: cell, byPlayerAt: opponent, existing: existing)
            return MoveEvaluation(
                cell: cell,
                ownGain: own.scoreIncrease,
                ownMultiplierAfter: own.multiplierAfter,
                opponentGain: theirs.scoreIncrease
            )
        }
    }
}
