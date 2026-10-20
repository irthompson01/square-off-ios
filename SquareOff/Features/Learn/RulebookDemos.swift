import SquareOffCore

/// A scripted move sequence played on a mini board inside the rulebook. Seats alternate
/// Blue (1), Red (2) from the first move, exactly like a real two-player game.
nonisolated struct RulebookDemo: Identifiable, Sendable {
    struct Move: Sendable {
        let row: Int
        let col: Int
        /// Shown under the board while this move is the latest one. `nil` derives a line from the result.
        var note: String? = nil
        /// Expected `scoreIncrease`, checked by the app tests so the scripts stay honest.
        var expect: Int? = nil
    }

    let id: String
    let size: Int
    let moves: [Move]

    var cells: [Cell] { moves.map { Cell(row: $0.row, col: $0.col) } }
}

nonisolated private func m(_ row: Int, _ col: Int, _ note: String? = nil, expect: Int? = nil) -> RulebookDemo.Move {
    RulebookDemo.Move(row: row, col: col, note: note, expect: expect)
}

/// One demo per animation on the web's instructions page.
nonisolated enum RulebookDemos {
    /// Blue forms a 2×2 square, then a 3×3 square.
    static let squares = RulebookDemo(id: "squares", size: 6, moves: [
        m(0, 0), m(5, 5), m(0, 1), m(5, 3), m(1, 0), m(5, 1),
        m(1, 1, "Four corners of a 2×2 square: +4", expect: 4),
        m(4, 0), m(1, 3), m(2, 0), m(1, 5), m(0, 5), m(3, 3), m(4, 2),
        m(3, 5, "A 3×3 square: +9. Only the corners matter.", expect: 9),
    ])

    /// Blue forms a 2×2 diamond, then a 3×3 diamond.
    static let diamonds = RulebookDemo(id: "diamonds", size: 6, moves: [
        m(0, 1), m(5, 5), m(1, 0), m(5, 0), m(2, 1), m(0, 5),
        m(1, 2, "Four tiles around a centre: a 2×2 diamond, +8", expect: 8),
        m(4, 0), m(1, 3), m(0, 4), m(3, 1), m(5, 1), m(5, 3), m(2, 5),
        m(3, 5, "A 3×3 diamond: +18", expect: 18),
    ])

    /// A 2-wide, 3-tall rectangle scores nothing.
    static let rectangles = RulebookDemo(id: "rectangles", size: 6, moves: [
        m(0, 0), m(5, 5), m(0, 1), m(5, 3), m(2, 0), m(3, 5),
        m(2, 1, "A rectangle, not a square: no points", expect: 0),
        m(5, 1), m(4, 1, "Still a rectangle (3×2): no points", expect: 0),
    ])

    /// 2×2, 3×3 and 4×4 squares: 4, 9 and 16 points.
    static let scoringSquares = RulebookDemo(id: "scoring-squares", size: 7, moves: [
        m(0, 0), m(0, 2), m(0, 1), m(1, 4), m(1, 0), m(2, 0),
        m(1, 1, "2×2 square: +4", expect: 4),
        m(4, 0), m(0, 3), m(5, 1), m(0, 5), m(4, 5), m(2, 3), m(1, 6),
        m(2, 5, "3×3 square: +9", expect: 9),
        m(5, 5), m(3, 3), m(2, 1), m(3, 6), m(4, 2), m(6, 3), m(0, 6),
        m(6, 6, "4×4 square: +16. Points equal the area.", expect: 16),
    ])

    /// 2×2 and 4×4 diamonds: 8 and 32 points (double the area).
    static let scoringDiamonds = RulebookDemo(id: "scoring-diamonds", size: 7, moves: [
        m(0, 1), m(6, 6), m(1, 0), m(6, 0), m(2, 1), m(0, 6),
        m(1, 2, "2×2 diamond: +8 (2 × 4)", expect: 8),
        m(5, 5), m(0, 3), m(4, 1), m(3, 0), m(1, 5), m(6, 3), m(5, 2),
        m(3, 6, "4×4 diamond: +32 (2 × 16)", expect: 32),
    ])

    /// One tile completes two 2×2 squares: (4 + 4) × 2.
    static let multiplierGain = RulebookDemo(id: "multiplier-gain", size: 6, moves: [
        m(0, 0), m(5, 5), m(0, 1), m(5, 3), m(0, 2), m(3, 5), m(1, 0), m(5, 1), m(1, 2), m(2, 5),
        m(1, 1, "Two shapes at once: (4 + 4) × 2 = 16, multiplier ×2", expect: 16),
    ])

    /// Keep completing two or more shapes and the multiplier keeps growing; one quiet move resets it.
    static let multiplierKeep = RulebookDemo(id: "multiplier-keep", size: 6, moves: [
        m(0, 0), m(5, 5), m(0, 1), m(5, 3), m(0, 2), m(3, 5), m(1, 0), m(5, 1), m(1, 2), m(2, 5), m(2, 0), m(4, 0),
        m(1, 1, "Two shapes: multiplier ×2", expect: 16),
        m(0, 4),
        m(2, 1, "Next turn, two more (a square and a diamond): 2 + 2 − 1 = ×3, so (4 + 8) × 3 = 36", expect: 36),
        m(4, 2),
        m(4, 4, "A turn with fewer than two shapes resets the multiplier to ×1", expect: 0),
    ])

    /// Two open diamond threats: Red can only block one.
    static let shapeOptions1 = RulebookDemo(id: "shape-options-1", size: 6, moves: [
        m(0, 1), m(5, 5), m(1, 0), m(5, 3),
        m(2, 1, "Blue threatens a diamond at the right"), m(3, 5), m(0, 4), m(5, 1), m(2, 4), m(4, 0),
        m(1, 5, "A second diamond threat: Red can block only one"),
        m(1, 2, "Red blocks the first"),
        m(1, 3, "Blue completes the other: +8", expect: 8),
    ])

    /// A square threat and a diamond threat at once.
    static let shapeOptions2 = RulebookDemo(id: "shape-options-2", size: 6, moves: [
        m(0, 0), m(5, 5), m(0, 1), m(5, 3),
        m(1, 0, "Blue threatens a 2×2 square"), m(3, 5), m(0, 3), m(5, 1), m(1, 2), m(4, 0),
        m(2, 3, "…and a 2×2 diamond"),
        m(1, 1, "Red blocks the square"),
        m(1, 4, "Blue takes the diamond: +8", expect: 8),
    ])

    /// A large square threat and a large diamond threat.
    static let shapeOptions3 = RulebookDemo(id: "shape-options-3", size: 6, moves: [
        m(0, 0), m(5, 5), m(0, 2), m(5, 0),
        m(2, 0, "Blue threatens a 3×3 square"), m(0, 5), m(1, 3), m(4, 4), m(3, 1), m(0, 4),
        m(5, 3, "…and a 3×3 diamond"),
        m(3, 5, "Red blocks the diamond"),
        m(2, 2, "Blue takes the square: +9", expect: 9),
    ])

    /// Two 2×2 diamonds completed by one tile.
    static let shapeStacks1 = RulebookDemo(id: "shape-stacks-1", size: 6, moves: [
        m(0, 1), m(5, 5), m(1, 0), m(5, 0), m(2, 1), m(0, 5), m(3, 2), m(4, 5), m(2, 3), m(5, 3),
        m(1, 2, "Two diamonds in one move: (8 + 8) × 2 = 32", expect: 32),
    ])

    /// Two 3×3 squares completed by one tile.
    static let shapeStacks2 = RulebookDemo(id: "shape-stacks-2", size: 6, moves: [
        m(0, 0), m(5, 5), m(0, 2), m(5, 0), m(2, 0), m(3, 5), m(0, 4), m(5, 1), m(2, 4), m(4, 3),
        m(2, 2, "Two 3×3 squares in one move: (9 + 9) × 2 = 36", expect: 36),
    ])

    /// Two 3×3 squares and a 3×3 diamond completed by one tile.
    static let shapeStacks3 = RulebookDemo(id: "shape-stacks-3", size: 7, moves: [
        m(0, 0), m(6, 6), m(0, 2), m(6, 0), m(2, 0), m(0, 6), m(0, 4), m(5, 1), m(2, 4), m(6, 3), m(4, 4), m(3, 6), m(2, 6), m(1, 5),
        m(2, 2, "Two squares and a diamond: (9 + 9 + 18) × 3 = 108", expect: 108),
    ])

    static let all: [RulebookDemo] = [
        squares, diamonds, rectangles, scoringSquares, scoringDiamonds, multiplierGain, multiplierKeep,
        shapeOptions1, shapeOptions2, shapeOptions3, shapeStacks1, shapeStacks2, shapeStacks3,
    ]
}
