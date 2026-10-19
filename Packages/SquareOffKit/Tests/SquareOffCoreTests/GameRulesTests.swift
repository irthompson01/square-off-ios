import Testing
@testable import SquareOffCore

private func twoPlayerGame(size: Int = 8) -> Game {
    Game(boardSize: size, players: [
        PlayerState(id: 1, name: "Blue", colorHex: "#0583D2"),
        PlayerState(id: 2, name: "Red", colorHex: "#FF3131", isCPU: true, cpuLevel: .maxMin),
    ])
}

/// Plays `moves` alternately (blue, red, blue, …) and returns every result.
@discardableResult
private func play(_ game: inout Game, _ moves: [(Int, Int)]) throws -> [MoveResult] {
    try moves.map { try game.place(at: Cell(row: $0.0, col: $0.1)) }
}

@Suite("Shape detection")
struct ShapeDetectionTests {
    @Test func twoByTwoSquareScoresFour() throws {
        var game = twoPlayerGame()
        let results = try play(&game, [(0, 0), (5, 5), (0, 1), (5, 7), (1, 0), (7, 5), (1, 1)])
        let last = try #require(results.last)
        #expect(last.newSquares.count == 1)
        #expect(last.newSquares.first?.points == 4)
        #expect(last.scoreIncrease == 4)
        #expect(game.players[0].score == 4)
    }

    @Test func twoByTwoDiamondScoresEight() throws {
        var game = twoPlayerGame(size: 3)
        let results = try play(&game, [(0, 1), (0, 0), (1, 0), (2, 2), (2, 1), (0, 2), (1, 2)])
        let last = try #require(results.last)
        #expect(last.newDiamonds.count == 1)
        #expect(last.newDiamonds.first?.points == 8)
        #expect(game.players[0].score == 8)
    }

    @Test func rectanglesDoNotCount() throws {
        var game = twoPlayerGame()
        let results = try play(&game, [(0, 0), (7, 0), (0, 2), (7, 2), (1, 0), (7, 4), (1, 2)])
        #expect(results.allSatisfy { $0.newShapeCount == 0 })
        #expect(game.players[0].score == 0)
    }

    @Test func existingShapesAreNotRecounted() throws {
        var game = twoPlayerGame()
        try play(&game, [(0, 0), (5, 5), (0, 1), (5, 7), (1, 0), (7, 5), (1, 1), (7, 7)])
        let next = try game.place(at: Cell(row: 3, col: 3))
        #expect(next.newShapeCount == 0)
        #expect(game.players[0].squares.count == 1)
    }

    @Test func squarePointsMatchRulebookTable() {
        for size in 2...8 {
            #expect(BoardShape(kind: .square, row: 0, col: 0, num: size - 1, ownerID: 1).points == size * size)
        }
        #expect(BoardShape(kind: .diamond, row: 0, col: 0, num: 1, ownerID: 1).points == 8)
        #expect(BoardShape(kind: .diamond, row: 0, col: 0, num: 2, ownerID: 1).points == 18)
        #expect(BoardShape(kind: .diamond, row: 0, col: 0, num: 3, ownerID: 1).points == 32)
    }
}

@Suite("Scoring and multipliers")
struct ScoringTests {
    /// Blue builds a 4×4 diamond (32), then one tile at (3,3) completes two 4×4 squares at once:
    /// multiplier 1 + 2 − 1 = 2, so (16 + 16) × 2 = 64 — the rulebook's own example.
    @Test func twoShapesInOneMoveDoubleTheScore() throws {
        var game = twoPlayerGame()
        let results = try play(&game, [
            (0, 0), (7, 0), (0, 3), (7, 1), (3, 0), (7, 2),
            (3, 6), (7, 4), (6, 3), (7, 5), (6, 6), (7, 6),
            (3, 3),
        ])

        let diamondMove = results[8]
        #expect(diamondMove.newDiamonds.count == 1)
        #expect(diamondMove.scoreIncrease == 32)
        #expect(diamondMove.multiplierAfter == 1)

        let doubleMove = try #require(results.last)
        #expect(doubleMove.newSquares.count == 2)
        #expect(doubleMove.multiplierAfter == 2)
        #expect(doubleMove.multiplierIncrease == 1)
        #expect(doubleMove.scoreIncrease == 64)
        #expect(game.players[0].score == 96)
    }

    @Test func multiplierResetsWithoutAShape() throws {
        var game = twoPlayerGame()
        try play(&game, [
            (0, 0), (7, 0), (0, 3), (7, 1), (3, 0), (7, 2),
            (3, 6), (7, 4), (6, 3), (7, 5), (6, 6), (7, 6),
            (3, 3), (7, 7),
        ])
        #expect(game.players[0].multiplier == 2)
        let quiet = try game.place(at: Cell(row: 5, col: 1))
        #expect(quiet.multiplierAfter == 1)
        #expect(quiet.scoreIncrease == 0)
    }

    @Test func spinTurnsFollowTheWebAnimationRule() throws {
        var game = twoPlayerGame()
        let results = try play(&game, [
            (0, 0), (7, 0), (0, 3), (7, 1), (3, 0), (7, 2),
            (3, 6), (7, 4), (6, 3), (7, 5), (6, 6), (7, 6),
            (3, 3),
        ])
        #expect(results[1].spinTurns == [Cell(row: 7, col: 0): 1])

        let spins = try #require(results.last).spinTurns
        // 2 shapes → each corner spins 2 × 2 = 4 turns; (3,3) is a corner of both → 8.
        #expect(spins[Cell(row: 0, col: 0)] == 4)
        #expect(spins[Cell(row: 3, col: 3)] == 8)
    }
}

@Suite("Turn flow and game end")
struct GameFlowTests {
    @Test func turnsRotateAndHistoryGrows() throws {
        var game = twoPlayerGame()
        #expect(game.currentPlayer.id == 1)
        try game.place(at: Cell(row: 0, col: 0))
        #expect(game.currentPlayer.id == 2)
        #expect(game.players.allSatisfy { $0.scoreHistory.count == 1 })
    }

    @Test func occupiedAndOutOfBoundsAreRejected() throws {
        var game = twoPlayerGame()
        try game.place(at: Cell(row: 0, col: 0))
        #expect(throws: MoveError.occupied) { try game.place(at: Cell(row: 0, col: 0)) }
        #expect(throws: MoveError.outOfBounds) { try game.place(at: Cell(row: 8, col: 0)) }
    }

    @Test func gameEndsWhenBoardIsFull() throws {
        var game = twoPlayerGame(size: 2)
        try play(&game, [(0, 0), (0, 1), (1, 0), (1, 1)])
        #expect(game.isOver)
        #expect(throws: MoveError.gameOver) { try game.place(at: Cell(row: 0, col: 0)) }
    }

    @Test func standingsBreakTiesByShapeCount() {
        var game = twoPlayerGame()
        var a = game.players[0]
        var b = game.players[1]
        a.score = 20
        b.score = 20
        b.squares = [BoardShape(kind: .square, row: 0, col: 0, num: 1, ownerID: 2)]
        game = Game(boardSize: 8, players: [a, b])
        #expect(game.standings.first?.id == 2)
        #expect(!game.isDraw)
    }

    @Test func cpuLevelsMatchTheWebNumbering() {
        #expect(CPULevel.allCases.map(\.number) == [1, 2, 3, 4, 5, 6])
        #expect(CPULevel(number: 3) == .cnn)
        #expect(CPULevel.maxMinIO.cpuType == "max-min-io")
    }
}
