import SquareOffCore
import Testing
@testable import SquareOff

/// Every rulebook demo must be a legal move sequence whose annotated scores match the engine.
@MainActor
struct RulebookDemoTests {
    @Test(arguments: RulebookDemos.all.map(\.id))
    func demoPlaysLegallyAndScoresAsAnnotated(id: String) throws {
        let demo = try #require(RulebookDemos.all.first { $0.id == id })
        var game = Game(boardSize: demo.size, players: [
            PlayerState(id: 1, name: "Blue", colorHex: "#000"),
            PlayerState(id: 2, name: "Red", colorHex: "#fff"),
        ])
        var sawAnnotatedMove = false
        for (index, move) in demo.moves.enumerated() {
            let cell = Cell(row: move.row, col: move.col)
            #expect(game.board[cell] == nil, "\(id): move \(index + 1) at \(cell) is occupied")
            let result = try game.place(at: cell)
            if let expect = move.expect {
                sawAnnotatedMove = true
                #expect(result.scoreIncrease == expect, "\(id): move \(index + 1) at \(cell) scored \(result.scoreIncrease), expected \(expect) (\(result.newShapes.map(\.id)))")
            } else if move.note == nil {
                // Filler moves must stay quiet so the story under the board stays accurate.
                #expect(result.newShapeCount == 0, "\(id): filler move \(index + 1) at \(cell) formed \(result.newShapes.map(\.id))")
            }
        }
        #expect(sawAnnotatedMove || id.hasPrefix("shape-options"), "\(id) has no annotated scoring move")
    }

    @Test func demosAreUnique() {
        #expect(Set(RulebookDemos.all.map(\.id)).count == RulebookDemos.all.count)
    }
}
