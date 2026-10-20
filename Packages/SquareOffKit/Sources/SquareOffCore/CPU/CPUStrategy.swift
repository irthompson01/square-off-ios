/// On-device port of the server's heuristic opponents (`server/src/routes/model.py`).
///
/// Every heuristic is a one-move lookahead that ends in exactly one uniform random pick over an
/// ordered list of candidates, so `candidates(in:)` is deterministic and `chooseMove` is just
/// `randomElement`. Level 3 (CNN) is a Keras model and has no on-device strategy.
public enum CPUStrategy: Sendable, Hashable, CaseIterable {
    case random
    case maxRandom
    case maxMin
    case maxMinOptimal
    case maxMinIO

    public init?(level: CPULevel) {
        switch level {
        case .random: self = .random
        case .maxRandom: self = .maxRandom
        case .maxMin: self = .maxMin
        case .maxMinOptimal: self = .maxMinOptimal
        case .maxMinIO: self = .maxMinIO
        case .cnn: return nil
        }
    }

    public var level: CPULevel {
        switch self {
        case .random: .random
        case .maxRandom: .maxRandom
        case .maxMin: .maxMin
        case .maxMinOptimal: .maxMinOptimal
        case .maxMinIO: .maxMinIO
        }
    }

    public func chooseMove(in game: Game) -> Cell {
        var rng = SystemRandomNumberGenerator()
        return chooseMove(in: game, using: &rng)
    }

    public func chooseMove(in game: Game, using rng: inout some RandomNumberGenerator) -> Cell {
        let options = candidates(in: game)
        precondition(!options.isEmpty, "No legal move: the game is over")
        return options.randomElement(using: &rng)!
    }

    /// The exact list the server would call `random.choice` on, in row-major order.
    /// Precondition: `!game.isOver`.
    public func candidates(in game: Game) -> [Cell] {
        let board = game.board
        let me = game.currentPlayer.id
        let empty = board.emptyCells

        switch self {
        case .random:
            return empty

        case .maxRandom:
            // `max_random`: best own gain, ties broken by multiplier (with the server's quirk that an
            // equal score with a higher multiplier appends instead of resetting the list), then prefer
            // cells not next to the mover's own tiles.
            var best: [Cell] = []
            var bestScore = 0
            var bestMultiplier = 1
            for move in MoveEvaluator.evaluate(game) {
                if move.ownGain > bestScore {
                    bestScore = move.ownGain
                    bestMultiplier = move.ownMultiplierAfter
                    best = [move.cell]
                } else if move.ownGain == bestScore {
                    if move.ownMultiplierAfter > bestMultiplier {
                        bestMultiplier = move.ownMultiplierAfter
                        best.append(move.cell)
                    } else if move.ownMultiplierAfter == bestMultiplier {
                        best.append(move.cell)
                    }
                }
            }
            guard best.count > 1 else { return best }
            let nonAdjacent = board.nonAdjacentCells(best, toTilesOf: me)
            return nonAdjacent.isEmpty ? best : nonAdjacent

        case .maxMin:
            // `max_min`: score if you can, else block the next player's best, else random non-adjacent.
            var scoring: [Cell] = []
            var bestScore = 0
            var blocking: [Cell] = []
            var bestBlock = 0
            for move in MoveEvaluator.evaluate(game) {
                if move.opponentGain > bestBlock {
                    bestBlock = move.opponentGain
                    blocking = [move.cell]
                } else if move.opponentGain == bestBlock, move.opponentGain > 0 {
                    blocking.append(move.cell)
                }
                if move.ownGain > bestScore {
                    bestScore = move.ownGain
                    scoring = [move.cell]
                } else if move.ownGain == bestScore, move.ownGain > 0 {
                    scoring.append(move.cell)
                }
            }
            if !scoring.isEmpty { return scoring }
            if !blocking.isEmpty { return blocking }
            let nonAdjacent = board.nonAdjacentCells(empty, toTilesOf: me)
            return nonAdjacent.isEmpty ? empty : nonAdjacent

        case .maxMinOptimal:
            // `max_min_optimal`: maximise max(own gain, opponent gain), else random non-adjacent.
            let best = bestByMaxGain(game)
            if !best.isEmpty { return best }
            let nonAdjacent = board.nonAdjacentCells(empty, toTilesOf: me)
            return nonAdjacent.isEmpty ? empty : nonAdjacent

        case .maxMinIO:
            // `max_min_inside_out`: as above, but the quiet fallback is the non-adjacent cell closest
            // to the centre.
            let best = bestByMaxGain(game)
            if !best.isEmpty { return best }
            let nonAdjacent = board.nonAdjacentCells(empty, toTilesOf: me)
            return board.cellsClosestToCenter(nonAdjacent.isEmpty ? empty : nonAdjacent)
        }
    }

    /// Cells with the highest `max(own, opponent)` gain, ignoring cells where that is 0.
    private func bestByMaxGain(_ game: Game) -> [Cell] {
        var best: [Cell] = []
        var bestScore = 0
        for move in MoveEvaluator.evaluate(game) {
            let score = max(move.ownGain, move.opponentGain)
            if score == 0 { continue }
            if score > bestScore {
                bestScore = score
                best = [move.cell]
            } else if score == bestScore {
                best.append(move.cell)
            }
        }
        return best
    }
}
