import SquareOffCore
import Testing
@testable import SquareOff

/// Every rulebook demo must be a legal sequence on the real engine, and the outcomes quoted in
/// the web's captions must hold.
@MainActor
struct RulebookDemoTests {
    private func play(_ demo: RulebookDemo) throws -> (game: Game, results: [MoveResult]) {
        var game = Game(boardSize: demo.size, players: RulebookDemo.players)
        for placement in demo.setup {
            #expect(game.board[placement.cell] == nil, "\(demo.id): setup tile \(placement.cell) is occupied")
            try game.place(at: placement.cell, by: placement.player)
        }
        var results: [MoveResult] = []
        for (index, move) in demo.moves.enumerated() {
            #expect(game.board[move.cell] == nil, "\(demo.id): move \(index + 1) at \(move.cell) is occupied")
            results.append(try game.place(at: move.cell, by: move.player))
        }
        return (game, results)
    }

    @Test(arguments: RulebookDemos.all.map(\.id))
    func demoPlaysLegally(id: String) throws {
        let demo = try #require(RulebookDemos.all.first { $0.id == id })
        _ = try play(demo)
    }

    @Test func demosAreUnique() {
        #expect(Set(RulebookDemos.all.map(\.id)).count == RulebookDemos.all.count)
        #expect(RulebookDemos.all.count == 13)
    }

    @Test func scoringDemosMatchTheirCaptions() throws {
        let squares = try play(RulebookDemos.scoringSquares).results
        #expect(squares.map(\.scoreIncrease).filter { $0 > 0 } == [4, 9])
        let diamonds = try play(RulebookDemos.scoringDiamonds).results
        #expect(diamonds.map(\.scoreIncrease).filter { $0 > 0 } == [8, 32])
        #expect(try play(RulebookDemos.rectangles).results.last?.newShapeCount == 0)
    }

    @Test func stackDemosMatchTheirCaptions() throws {
        #expect(try play(RulebookDemos.shapeStacks1).results.last?.scoreIncrease == 32)
        #expect(try play(RulebookDemos.shapeStacks2).results.last?.scoreIncrease == 36)
        let stacks3 = try play(RulebookDemos.shapeStacks3).results.last
        #expect(stacks3?.scoreIncrease == 108 && stacks3?.newShapeCount == 3 && stacks3?.multiplierAfter == 3)
    }

    @Test func multiplierDemosGrowAndReset() throws {
        let getting = try play(RulebookDemos.multsGetting)
        #expect(getting.results.last?.newShapeCount == 2 && getting.results.last?.multiplierAfter == 2)
        let keeping = try play(RulebookDemos.multsKeeping)
        let blueMoves = keeping.results.filter { $0.playerID == 1 }
        #expect(blueMoves.map(\.multiplierAfter) == [2, 3, 1])
    }

    @Test func captionsFollowTheWebWording() throws {
        let getting = try play(RulebookDemos.multsGetting)
        let last = try #require(getting.results.last)
        let blue = try #require(getting.game.players.first { $0.id == 1 })
        #expect(DemoBoardView.describe(last, by: blue).hasPrefix("Blue completes a "))
        let caption = DemoBoardView.describe(last, by: blue)
        #expect(caption.contains(" at once: (4 + 9) × 2 = 26") || caption.contains(" at once: (9 + 4) × 2 = 26"), "\(caption)")
    }
}
