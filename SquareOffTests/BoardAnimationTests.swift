import SquareOffCore
import Testing
@testable import SquareOff

struct BoardAnimationTests {
    private func square(at row: Int, _ col: Int, num: Int = 1, owner: Int = 1) -> BoardShape {
        BoardShape(kind: .square, row: row, col: col, num: num, ownerID: owner)
    }

    private func move(cell: Cell, squares: [BoardShape] = [], diamonds: [BoardShape] = []) -> MoveResult {
        var game = Game(boardSize: 6, players: [
            PlayerState(id: 1, name: "A", colorHex: "#4C8BF5"),
            PlayerState(id: 2, name: "B", colorHex: "#DD5144"),
        ])
        // Play the real move so MoveResult is genuine; a 2×2 square at the top-left needs three
        // Blue tiles first with Red moves in between.
        for c in [Cell(row: 0, col: 0), Cell(row: 5, col: 5), Cell(row: 0, col: 1), Cell(row: 5, col: 4), Cell(row: 1, col: 0), Cell(row: 5, col: 3)] {
            _ = try? game.place(at: c)
        }
        return (try? game.place(at: cell)) ?? MoveResult(cell: cell, playerID: 1, newSquares: squares, newDiamonds: diamonds, scoreIncrease: 0, multiplierIncrease: 0, scoreAfter: 0, multiplierAfter: 1)
    }

    @Test func plainPlacementSchedulesNothing() {
        let result = move(cell: Cell(row: 3, col: 3))
        #expect(result.newShapeCount == 0)
        #expect(SpinSchedule.events(for: result, sequence: 1, continuousIndex: false).isEmpty)
    }

    @Test func resultsWaitForTheLastSpin() {
        // Nothing to spin: only the flip, so the web's 1.6 s floor applies.
        #expect(SpinSchedule.completion(of: [:]) == SpinSchedule.flipDuration)
        #expect(SpinSchedule.resultsDelay(for: [:]) == 1.6)
        // A two-shape move: the last corner starts at 3 × 45 ms (+ the tapped tile's flip) and
        // spins four quarter turns, 1.44 s, so the sheet waits for it.
        let events = [
            Cell(row: 0, col: 0): SpinEvent(id: 1, turns: 4, delay: 0.32),
            Cell(row: 0, col: 1): SpinEvent(id: 1, turns: 4, delay: 0.045),
            Cell(row: 1, col: 0): SpinEvent(id: 1, turns: 4, delay: 0.09),
            Cell(row: 1, col: 1): SpinEvent(id: 1, turns: 4, delay: 0.135),
        ]
        #expect(abs(SpinSchedule.completion(of: events) - (0.32 + 1.44)) < 0.001)
        #expect(abs(SpinSchedule.resultsDelay(for: events) - (0.32 + 1.44 + 0.3)) < 0.001)
        #expect(SpinSchedule.resultsDelay(for: events, reduceMotion: true) == 1.6)
    }

    @Test func squareCornersStaggerInReadingOrderAfterTheFlip() {
        let result = move(cell: Cell(row: 1, col: 1))   // completes the 2×2 at (0,0)
        #expect(result.newSquares.count == 1)
        let events = SpinSchedule.events(for: result, sequence: 7, continuousIndex: false)
        #expect(events.count == 4)
        #expect(events[Cell(row: 0, col: 0)]?.delay == 0)
        #expect(events[Cell(row: 0, col: 1)]?.delay == 0.045)
        #expect(events[Cell(row: 1, col: 0)]?.delay == 0.09)
        // The tapped tile (BR) is fourth and waits for its flip too.
        #expect(events[Cell(row: 1, col: 1)]?.delay == 0.135 + SpinSchedule.flipDuration)
        #expect(events.values.allSatisfy { $0.turns == 2 && $0.id == 7 })
        #expect(events[Cell(row: 0, col: 0)]?.degrees == 180)
        #expect(events[Cell(row: 0, col: 0)]?.duration == 0.72)
    }

    @Test func sharedCornerGetsOneEvent() {
        let shapes = [square(at: 0, 0), square(at: 1, 1)]   // share corner (1,1)
        let result = MoveResult(cell: Cell(row: 1, col: 1), playerID: 1, newSquares: shapes, newDiamonds: [],
                                scoreIncrease: 16, multiplierIncrease: 1, scoreAfter: 16, multiplierAfter: 2)
        let events = SpinSchedule.events(for: result, sequence: 1, continuousIndex: false)
        #expect(events.count == 7)
        #expect(events.values.allSatisfy { $0.turns == 4 })
    }

    @Test func diamondBatchRestartsLocallyButNotOnline() {
        let diamond = BoardShape(kind: .diamond, row: 2, col: 2, num: 1, ownerID: 1)
        let result = MoveResult(cell: Cell(row: 5, col: 5), playerID: 1, newSquares: [square(at: 0, 0)], newDiamonds: [diamond],
                                scoreIncrease: 24, multiplierIncrease: 1, scoreAfter: 24, multiplierAfter: 2)
        let local = SpinSchedule.events(for: result, sequence: 1, continuousIndex: false)
        let online = SpinSchedule.events(for: result, sequence: 1, continuousIndex: true)
        let top = Cell(row: 2, col: 3)
        #expect(local[top]?.delay == 0)
        #expect(online[top]?.delay == 4 * SpinSchedule.stagger)
    }

    @Test func shapeAgeFormula() {
        #expect(ShapeAge.opacity(order: 10, newest: 10, visibleCount: 11) == 1)
        #expect(ShapeAge.opacity(order: 5, newest: 10, visibleCount: 11) == 1)       // age 5 still full
        #expect(ShapeAge.opacity(order: 0, newest: 10, visibleCount: 11) == 0.4)     // oldest: 1 − 0.6
        #expect(abs(ShapeAge.opacity(order: 41, newest: 41, visibleCount: 42) - 0.88) < 1e-9)   // soften 1 → 1 − 0.12
        #expect(abs(ShapeAge.opacity(order: 0, newest: 60, visibleCount: 61) - 0.32) < 1e-9)   // 0.4 × 0.8
        #expect(ShapeAge.opacity(order: 0, newest: 200, visibleCount: 201) >= 0.25)
    }
}
