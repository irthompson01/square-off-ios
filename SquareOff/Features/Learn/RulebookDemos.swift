import SquareOffCore

/// A scripted example for the rulebook, played on the real rules engine (web
/// `demo-scenarios.ts`). `setup` tiles are placed instantly when the demo (re)starts; `moves`
/// play one by one. Player 1 is Blue, player 2 is Red; moves name their player explicitly.
nonisolated struct RulebookDemo: Identifiable, Sendable {
    struct Placement: Sendable {
        let player: Int
        let row: Int
        let col: Int
        var cell: Cell { Cell(row: row, col: col) }
    }

    struct Move: Sendable {
        let player: Int
        let row: Int
        let col: Int
        /// Replaces the auto-generated caption for this move.
        var note: String? = nil
        var cell: Cell { Cell(row: row, col: col) }
    }

    let id: String
    let size: Int
    var setup: [Placement] = []
    let moves: [Move]

    static let players = [
        PlayerState(id: 1, name: "Blue", colorHex: "#4C8BF5"),
        PlayerState(id: 2, name: "Red", colorHex: "#DD5144"),
    ]
}

nonisolated private func s(_ player: Int, _ row: Int, _ col: Int) -> RulebookDemo.Placement {
    RulebookDemo.Placement(player: player, row: row, col: col)
}

nonisolated private func m(_ player: Int, _ row: Int, _ col: Int, _ note: String? = nil) -> RulebookDemo.Move {
    RulebookDemo.Move(player: player, row: row, col: col, note: note)
}

/// The web's thirteen scenarios, verbatim (player 0 → 1, player 1 → 2).
nonisolated enum RulebookDemos {
    /// Both players build squares in their own corners: Blue a 2×2 and a 4×4, Red a 3×3 and a 2×2.
    static let squares = RulebookDemo(id: "squares", size: 7,
        setup: [s(1, 0, 0), s(2, 0, 4), s(1, 3, 0), s(2, 5, 5)],
        moves: [m(1, 0, 1), m(2, 0, 6), m(1, 1, 0), m(2, 2, 4), m(1, 1, 1), m(2, 2, 6), m(1, 3, 3), m(2, 5, 6), m(1, 6, 0), m(2, 6, 5), m(1, 6, 3), m(2, 6, 6)])

    /// Both players build diamonds: Blue a 3×3 and a 2×2, Red a 2×2 and a 3×3.
    static let diamonds = RulebookDemo(id: "diamonds", size: 8,
        setup: [s(1, 0, 2), s(2, 3, 5), s(1, 5, 1), s(2, 0, 6)],
        moves: [m(1, 2, 4), m(2, 5, 7), m(1, 2, 0), m(2, 7, 5), m(1, 4, 2), m(2, 5, 3), m(1, 6, 2), m(2, 1, 7), m(1, 7, 1), m(2, 2, 6), m(1, 6, 0), m(2, 1, 5)])

    /// Four corners of a wider-than-tall rectangle score nothing.
    static let rectangles = RulebookDemo(id: "rectangles", size: 6, moves: [
        m(1, 1, 0), m(2, 5, 5), m(1, 1, 4), m(2, 5, 1), m(1, 3, 0), m(2, 0, 5),
        m(1, 3, 4, "Blue closes a 5-wide, 3-tall rectangle: not a square, so no points"),
    ])

    /// A 2×2 square (4) then a 3×3 square (9).
    static let scoringSquares = RulebookDemo(id: "scoringSquares", size: 6,
        setup: [s(1, 4, 4), s(2, 0, 5), s(1, 4, 5), s(2, 3, 1)],
        moves: [m(1, 5, 4), m(2, 1, 4), m(1, 5, 5), m(2, 5, 1), m(1, 0, 0), m(2, 3, 3), m(1, 0, 2), m(2, 4, 0), m(1, 2, 0), m(2, 1, 1), m(1, 2, 2)])

    /// A 2×2 diamond (8) then a 4×4 diamond (32).
    static let scoringDiamonds = RulebookDemo(id: "scoringDiamonds", size: 7,
        setup: [s(1, 0, 5), s(2, 6, 6), s(1, 1, 6), s(2, 5, 0), s(1, 1, 4), s(2, 6, 1)],
        moves: [m(1, 2, 5), m(2, 4, 4), m(1, 0, 3), m(2, 2, 1), m(1, 3, 6), m(2, 5, 5), m(1, 3, 0), m(2, 4, 2), m(1, 6, 3)])

    /// One tile completes two shapes: multiplier ×2.
    static let multsGetting = RulebookDemo(id: "multsGetting", size: 6,
        setup: [s(1, 0, 0), s(2, 5, 5), s(1, 0, 1), s(2, 5, 0), s(1, 1, 0), s(2, 0, 5), s(1, 1, 3), s(2, 4, 4), s(1, 3, 1)],
        moves: [m(2, 5, 3), m(1, 3, 3), m(2, 2, 5), m(1, 1, 1)])

    /// Two shapes (×2), two shapes again (×3), then no shape (back to ×1).
    static let multsKeeping = RulebookDemo(id: "multsKeeping", size: 6,
        setup: [s(1, 0, 0), s(1, 0, 1), s(1, 1, 0), s(1, 1, 3), s(1, 3, 1), s(1, 3, 3), s(1, 4, 5), s(1, 5, 4), s(1, 5, 5), s(1, 4, 2), s(1, 5, 3), s(2, 5, 0), s(2, 2, 5), s(2, 0, 5)],
        moves: [m(1, 1, 1), m(2, 0, 4), m(1, 4, 4), m(2, 2, 4),
                m(1, 2, 0, "Blue forms no shape this turn, so the multiplier resets to ×1")])

    /// One move opens two diamonds; Red can only block one.
    static let shapeOptions1 = RulebookDemo(id: "shapeOptions1", size: 6,
        setup: [s(1, 0, 1), s(2, 5, 5), s(1, 1, 0), s(2, 4, 0), s(1, 0, 3), s(2, 5, 2), s(1, 1, 4)],
        moves: [m(2, 4, 4), m(1, 1, 2, "Blue threatens two 2×2 diamonds at once"), m(2, 2, 1, "Red can only block one of them"), m(1, 2, 3)])

    /// A diamond threat plus a square threat.
    static let shapeOptions2 = RulebookDemo(id: "shapeOptions2", size: 6,
        setup: [s(1, 0, 1), s(2, 0, 4), s(1, 1, 0), s(2, 4, 0), s(1, 1, 2), s(2, 2, 4), s(1, 3, 3), s(2, 5, 1), s(1, 3, 5)],
        moves: [m(2, 0, 5), m(1, 5, 3, "Blue now threatens a 2×2 diamond and a 3×3 square"), m(2, 5, 5, "Red blocks the square"), m(1, 2, 1)])

    /// Three threats at once: a 4×4 square, a 3×3 square and a diamond.
    static let shapeOptions3 = RulebookDemo(id: "shapeOptions3", size: 7,
        setup: [s(1, 0, 0), s(2, 1, 5), s(1, 0, 3), s(2, 2, 6), s(1, 3, 0), s(2, 0, 6), s(1, 4, 4), s(2, 2, 2), s(1, 4, 6), s(2, 1, 1), s(1, 6, 4), s(2, 3, 5), s(1, 4, 1), s(2, 6, 6), s(1, 5, 2)],
        moves: [m(2, 0, 2), m(1, 6, 1, "Blue threatens a 4×4 square and a 2×2 diamond"), m(2, 3, 3, "Red blocks the 4×4 square (worth 16)"), m(1, 5, 0)])

    /// One tile completes two 2×2 diamonds.
    static let shapeStacks1 = RulebookDemo(id: "shapeStacks1", size: 6,
        setup: [s(1, 0, 1), s(2, 5, 5), s(1, 1, 0), s(2, 4, 0), s(1, 2, 1), s(2, 0, 4), s(1, 2, 3)],
        moves: [m(2, 5, 2), m(1, 3, 2), m(2, 4, 5), m(1, 1, 2)])

    /// One tile completes two 3×3 squares.
    static let shapeStacks2 = RulebookDemo(id: "shapeStacks2", size: 6,
        setup: [s(1, 0, 0), s(2, 5, 5), s(1, 0, 2), s(2, 4, 1), s(1, 0, 4), s(2, 3, 3), s(1, 2, 0)],
        moves: [m(2, 5, 2), m(1, 2, 4), m(2, 4, 5), m(1, 2, 2)])

    /// One tile completes two 3×3 squares and a 3×3 diamond.
    static let shapeStacks3 = RulebookDemo(id: "shapeStacks3", size: 7,
        setup: [s(1, 0, 0), s(2, 6, 6), s(1, 0, 2), s(2, 5, 1), s(1, 0, 4), s(2, 6, 3), s(1, 2, 0), s(2, 4, 1), s(1, 2, 4)],
        moves: [m(2, 6, 0), m(1, 2, 6), m(2, 5, 5), m(1, 4, 4), m(2, 3, 1), m(1, 2, 2)])

    static let all: [RulebookDemo] = [
        squares, diamonds, rectangles, scoringSquares, scoringDiamonds, multsGetting, multsKeeping,
        shapeOptions1, shapeOptions2, shapeOptions3, shapeStacks1, shapeStacks2, shapeStacks3,
    ]
}
