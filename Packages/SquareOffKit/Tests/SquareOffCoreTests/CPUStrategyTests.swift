import Testing
@testable import SquareOffCore

// MARK: - Fixtures

/// Builds a game from ASCII rows (`.` = empty, a digit = that seat's tile). Shapes already complete
/// on the board are credited to their owner so the evaluator doesn't count them as new, mirroring
/// the `squares`/`diamonds` lists the web client sends the server.
private func fixture(
    _ rows: [String],
    current: Int = 2,
    seats: Int? = nil,
    multipliers: [Int: Int] = [:]
) -> Game {
    let size = rows.count
    var board = Board(size: size)
    var maxSeat = 2
    for (r, row) in rows.enumerated() {
        precondition(row.count == size, "Fixture rows must be square")
        for (c, char) in row.enumerated() where char != "." {
            let seat = Int(String(char))!
            board[r, c] = seat
            maxSeat = max(maxSeat, seat)
        }
    }
    let count = seats ?? maxSeat
    var players = (1...count).map {
        PlayerState(id: $0, name: "P\($0)", colorHex: "#000000", isCPU: $0 != 1, cpuLevel: $0 != 1 ? .maxMin : nil)
    }
    for shape in board.findNewSquares(excluding: []) { players[shape.ownerID - 1].squares.append(shape) }
    for shape in board.findNewDiamonds(excluding: []) { players[shape.ownerID - 1].diamonds.append(shape) }
    for (seat, multiplier) in multipliers { players[seat - 1].multiplier = multiplier }
    return Game(board: board, players: players, currentPlayerIndex: current - 1)
}

private func cell(_ row: Int, _ col: Int) -> Cell { Cell(row: row, col: col) }

private func cells(_ pairs: (Int, Int)...) -> Set<Cell> { Set(pairs.map { Cell(row: $0.0, col: $0.1) }) }

private func candidates(_ strategy: CPUStrategy, _ game: Game) -> Set<Cell> {
    Set(strategy.candidates(in: game))
}

/// Seat 2 can complete a 2×2 at (1,1) for 4; seat 1 could complete a 4×4 at (7,7) for 16.
private let scoreOrBlock = [
    "22......",
    "2.......",
    "........",
    "........",
    "....1..1",
    "........",
    "........",
    "....1...",
]

/// Seat 2 completes a 4×4 (16, ×1) at (3,3) and two 2×2s at (6,6) (8 × 2 = 16, ×2), but (6,6)
/// touches its own tile at (5,6).
private let equalScoreButAdjacent = [
    "2..2....",
    "........",
    "........",
    "2.......",
    "........",
    ".....222",
    ".....2.2",
    "........",
]

/// Seat 2 completes a 6×6 (36, ×1) at (0,0) and two 3×3s at (7,7) (18 × 2 = 36, ×2). Neither cell
/// touches an own tile. Row-major order: (0,0) is evaluated before (7,7).
private let equalScoreBiggerMultiplierLater = [
    ".....2....",
    "..........",
    "..........",
    "..........",
    "..........",
    "2....2.2.2",
    "..........",
    ".....2...2",
    "..........",
    "..........",
]

/// The same position rotated so the two-shape cell (2,2) is evaluated before the 6×6 cell (9,9).
private let equalScoreBiggerMultiplierFirst = [
    "..........",
    "..........",
    "2...2.....",
    "..........",
    "2.2.2....2",
    "..........",
    "..........",
    "..........",
    "..........",
    "....2.....",
]

// MARK: - Board helpers

@Suite("Board geometry")
struct BoardGeometryTests {
    @Test func nonAdjacencyChecksOwnTilesOrEveryone() {
        var board = Board(size: 4)
        board[1, 1] = 1
        board[3, 3] = 2
        let empty = board.emptyCells

        let ownOnly = Set(board.nonAdjacentCells(empty, toTilesOf: 1))
        #expect(ownOnly.isDisjoint(with: cells((0, 1), (2, 1), (1, 0), (1, 2))))
        #expect(ownOnly.isSuperset(of: cells((2, 3), (3, 2))))

        let everyone = Set(board.nonAdjacentCells(empty, toTilesOf: nil))
        #expect(everyone.isDisjoint(with: cells((0, 1), (2, 1), (1, 0), (1, 2), (2, 3), (3, 2))))
        #expect(everyone.count == empty.count - 6)
    }

    @Test func nonAdjacencyPreservesOrderAndIgnoresDiagonals() {
        var board = Board(size: 3)
        board[1, 1] = 1
        let result = board.nonAdjacentCells(board.emptyCells, toTilesOf: 1)
        #expect(result == [cell(0, 0), cell(0, 2), cell(2, 0), cell(2, 2)])
    }

    @Test func closestToCenterKeepsEveryTie() {
        let even = Board(size: 8)
        #expect(Set(even.cellsClosestToCenter(even.emptyCells)) == cells((3, 3), (3, 4), (4, 3), (4, 4)))

        let odd = Board(size: 7)
        #expect(odd.cellsClosestToCenter(odd.emptyCells) == [cell(3, 3)])

        let corners = [cell(0, 0), cell(7, 7), cell(0, 7), cell(1, 1)]
        #expect(even.cellsClosestToCenter(corners) == [cell(1, 1)])
        #expect(even.cellsClosestToCenter(Array(corners.prefix(3))) == Array(corners.prefix(3)))
    }
}

// MARK: - Preview

@Suite("Placement preview")
struct PlacementPreviewTests {
    @Test func previewMatchesPlaceAndDoesNotMutate() throws {
        var rng = SplitMix64(seed: 7)
        var game = Game(boardSize: 6, players: [
            PlayerState(id: 1, name: "A", colorHex: "#000"),
            PlayerState(id: 2, name: "B", colorHex: "#fff"),
        ])
        var sawAShape = false
        while !game.isOver {
            let cell = game.board.emptyCells.randomElement(using: &rng)!
            let before = game
            let preview = game.preview(placing: cell, byPlayerAt: game.currentPlayerIndex)
            #expect(game == before)

            let result = try game.place(at: cell)
            #expect(result.newSquares == preview.newSquares)
            #expect(result.newDiamonds == preview.newDiamonds)
            #expect(result.scoreIncrease == preview.scoreIncrease)
            #expect(result.multiplierAfter == preview.multiplierAfter)
            #expect(result.multiplierIncrease == preview.multiplierIncrease)
            sawAShape = sawAShape || preview.newShapeCount > 0
        }
        #expect(sawAShape, "A full 6×6 game should score at least once")
    }

    @Test func previewAppliesTheMoverCurrentMultiplier() {
        // Seat 2 completes two 3×3 squares at (7,7) with multiplier 3: (9 + 9) × (3 + 2 − 1) = 72.
        let game = fixture(equalScoreBiggerMultiplierLater, multipliers: [2: 3])
        let evaluation = MoveEvaluator.evaluate(game).first { $0.cell == cell(7, 7) }!
        #expect(evaluation.ownGain == 72)
        #expect(evaluation.ownMultiplierAfter == 4)
    }
}

// MARK: - Strategies

@Suite("Random")
struct RandomStrategyTests {
    @Test func everyEmptyCellIsACandidate() {
        let game = fixture(scoreOrBlock)
        #expect(CPUStrategy.random.candidates(in: game) == game.board.emptyCells)
    }
}

@Suite("Max-Random")
struct MaxRandomTests {
    @Test func scoringBeatsNotScoring() {
        #expect(candidates(.maxRandom, fixture(scoreOrBlock)) == cells((1, 1)))
    }

    @Test func equalScoreWithHigherMultiplierAppendsInsteadOfResetting() {
        // 6×6 (36, ×1) is seen first, then the double 3×3 (36, ×2): the server appends → both kept.
        #expect(candidates(.maxRandom, fixture(equalScoreBiggerMultiplierLater)) == cells((0, 0), (7, 7)))
        // Seen the other way round, the lower-multiplier cell is dropped.
        #expect(candidates(.maxRandom, fixture(equalScoreBiggerMultiplierFirst)) == cells((2, 2)))
    }

    @Test func tiedScoringMovesPreferCellsAwayFromOwnTiles() {
        // Both cells score 16, but (6,6) is next to the mover's tile at (5,6).
        #expect(candidates(.maxRandom, fixture(equalScoreButAdjacent)) == cells((3, 3)))
    }

    @Test func quietPositionPrefersCellsAwayFromOwnTiles() {
        let game = fixture([
            "2...",
            "....",
            "....",
            "...1",
        ])
        let expected = Set(game.board.emptyCells).subtracting(cells((0, 1), (1, 0)))
        #expect(candidates(.maxRandom, game) == expected)
    }

    @Test func fallsBackToEveryTieWhenAllAreAdjacent() {
        let game = fixture([
            "2.",
            ".2",
        ])
        #expect(candidates(.maxRandom, game) == cells((0, 1), (1, 0)))
    }
}

@Suite("Max-Min")
struct MaxMinTests {
    @Test func scoringBeatsALargerBlock() {
        #expect(candidates(.maxMin, fixture(scoreOrBlock)) == cells((1, 1)))
    }

    @Test func blocksWhenItCannotScore() {
        var rows = scoreOrBlock
        rows[0] = "........"
        rows[1] = "........"
        #expect(candidates(.maxMin, fixture(rows)) == cells((7, 7)))
    }

    @Test func quietPositionPrefersCellsAwayFromOwnTiles() {
        let game = fixture([
            "2...",
            "....",
            "....",
            "...1",
        ])
        let expected = Set(game.board.emptyCells).subtracting(cells((0, 1), (1, 0)))
        #expect(candidates(.maxMin, game) == expected)
    }

    @Test func fallsBackToEveryCellWhenAllAreAdjacent() {
        let game = fixture([
            "2.",
            ".2",
        ])
        #expect(candidates(.maxMin, game) == cells((0, 1), (1, 0)))
    }
}

@Suite("Max-Min-Optimal")
struct MaxMinOptimalTests {
    @Test func takesTheLargerOfScoringAndBlocking() {
        #expect(candidates(.maxMinOptimal, fixture(scoreOrBlock)) == cells((7, 7)))
    }

    @Test func keepsBothSidesOfATie() {
        let game = fixture([
            "22......",
            "2.......",
            "........",
            "........",
            "........",
            ".....11.",
            ".....1..",
            "........",
        ])
        #expect(candidates(.maxMinOptimal, game) == cells((1, 1), (6, 6)))
    }

    @Test func opponentGainUsesTheOpponentMultiplier() {
        // Seat 1 (next) would complete two 2×2s at (6,6): 8 × 1 with a fresh multiplier, 8 × 3 with ×2.
        let rows = [
            "........",
            "........",
            "........",
            "........",
            "........",
            ".....111",
            ".....1.1",
            "........",
        ]
        let fresh = MoveEvaluator.evaluate(fixture(rows)).first { $0.cell == cell(6, 6) }!
        #expect(fresh.opponentGain == 16)
        let boosted = MoveEvaluator.evaluate(fixture(rows, multipliers: [1: 2])).first { $0.cell == cell(6, 6) }!
        #expect(boosted.opponentGain == 24)
        #expect(candidates(.maxMinOptimal, fixture(rows)) == cells((6, 6)))
    }

    @Test func onlyTheNextSeatCountsAsTheOpponent() {
        // Seat 1 to move. Seat 2 (next) can complete a 2×2 at (1,1). Seat 3 could complete a 4×4 at
        // (7,7), but the heuristic never looks past the next seat.
        let game = fixture([
            "22......",
            "2.......",
            "........",
            "........",
            "....3..3",
            "........",
            "........",
            "....3...",
        ], current: 1)
        #expect(game.players.count == 3)
        #expect(candidates(.maxMinOptimal, game) == cells((1, 1)))
        let far = MoveEvaluator.evaluate(game).first { $0.cell == cell(7, 7) }!
        #expect(far.opponentGain == 0)
    }

    @Test func quietPositionPrefersCellsAwayFromOwnTiles() {
        let game = fixture([
            "2...",
            "....",
            "....",
            "...1",
        ])
        let expected = Set(game.board.emptyCells).subtracting(cells((0, 1), (1, 0)))
        #expect(candidates(.maxMinOptimal, game) == expected)
    }
}

@Suite("Max-Min-IO")
struct MaxMinIOTests {
    @Test func opensInTheCentre() {
        let eight = fixture(Array(repeating: "........", count: 8))
        #expect(candidates(.maxMinIO, eight) == cells((3, 3), (3, 4), (4, 3), (4, 4)))

        let seven = fixture(Array(repeating: ".......", count: 7))
        #expect(candidates(.maxMinIO, seven) == cells((3, 3)))
    }

    @Test func scoresOrBlocksLikeOptimal() {
        #expect(candidates(.maxMinIO, fixture(scoreOrBlock)) == cells((7, 7)))
    }

    @Test func quietFallbackIsClosestToCentreAmongNonAdjacentCells() {
        // Own tile at (3,3), opponent at (4,4). Cells next to (3,3) are out; cells next to (4,4) are fine.
        let game = fixture([
            "........",
            "........",
            "........",
            "...2....",
            "....1...",
            "........",
            "........",
            "........",
        ])
        #expect(candidates(.maxMinIO, game) == cells((2, 4), (3, 5), (4, 2), (4, 5), (5, 3), (5, 4)))
    }
}

@Suite("Levels")
struct CPULevelMappingTests {
    @Test func everyOfflineLevelHasAStrategyAndCNNDoesNot() {
        #expect(CPUStrategy(level: .cnn) == nil)
        #expect(!CPULevel.cnn.isAvailableOffline)
        #expect(CPULevel.cnn.offlineFallback == .maxMinOptimal)
        for level in CPULevel.allCases where level != .cnn {
            #expect(level.isAvailableOffline)
            #expect(level.offlineFallback == level)
            #expect(CPUStrategy(level: level)?.level == level)
        }
        #expect(Set(CPUStrategy.allCases.map(\.level)).count == 5)
    }
}
