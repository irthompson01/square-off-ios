/// The web's rulebook (`hero-client/src/data/rulebook-content.ts`), block for block. Where the
/// web shows a GIF, the app plays the same idea on a live mini board (`RulebookDemos`).
enum Rulebook {
    enum Theme: String {
        case sky, emerald, amber, violet, rose, slate

        var hex: String {
            switch self {
            case .sky: "#38BDF8"
            case .emerald: "#34D399"
            case .amber: "#FBBF24"
            case .violet: "#A78BFA"
            case .rose: "#FB7185"
            case .slate: "#94A3B8"
            }
        }
    }

    enum Callout: String {
        case tip, note, strategy

        var symbol: String {
            switch self {
            case .tip: "lightbulb"
            case .note: "info.circle"
            case .strategy: "flag.checkered"
            }
        }
    }

    enum Block: Identifiable {
        case paragraph(String)
        case subtitle(String)
        case list([String], ordered: Bool = false)
        case table(caption: String?, columns: (String, String), rows: [(String, String)])
        case demo(RulebookDemo, caption: String?)
        case callout(Callout, title: String?, text: String)
        case formula(lines: [String], caption: String?)

        var id: String {
            switch self {
            case .paragraph(let t), .subtitle(let t): t
            case .list(let items, _): items.joined()
            case .table(let caption, let columns, _): (caption ?? "") + columns.0 + columns.1
            case .demo(let demo, _): demo.id
            case .callout(_, let title, let text): (title ?? "") + text
            case .formula(let lines, _): lines.joined()
            }
        }
    }

    struct Subsection: Identifiable {
        let id: String
        let title: String
        let blocks: [Block]
    }

    struct Section: Identifiable {
        let id: String
        let title: String
        let eyebrow: String?
        let theme: Theme
        let intro: String?
        let blocks: [Block]
        var subsections: [Subsection] = []
        /// Short label for the navigation chips (`RULEBOOK_NAV`).
        let navLabel: String
        let navDescription: String
    }

    static let sections: [Section] = [
        Section(
            id: "section-intro",
            title: "Introduction & objective",
            eyebrow: "Welcome",
            theme: .sky,
            intro: "Square Off is a turn-based strategy game for 2 to 4 players. This guide explains the rules, scoring, multipliers, and ideas you can use to improve. Use the navigation to jump to what you need.",
            blocks: [
                .paragraph("Whether you are new or experienced, the same core idea applies: score the most points by claiming tiles and forming Squares and Diamonds. When every tile is filled, the highest score wins."),
                .callout(.note, title: "Objective", text: "End the game with more points than your opponents by forming valid shapes and managing multipliers."),
            ],
            navLabel: "Start here",
            navDescription: "What Square Off is and how you win"
        ),
        Section(
            id: "section-modes",
            title: "Game modes",
            eyebrow: "How to play",
            theme: .emerald,
            intro: "Choose how you want to compete.",
            blocks: [
                .list([
                    "Single player: play against a computer opponent.",
                    "Multiplayer local: 2 to 4 players on one device, passing turns.",
                    "Multiplayer online: host or join a room and play in real time.",
                ]),
            ],
            navLabel: "Game modes",
            navDescription: "Single player, local, and online"
        ),
        Section(
            id: "section-setup",
            title: "Setup & turn order",
            eyebrow: "Basics",
            theme: .slate,
            intro: "Games use a square grid (commonly 8 by 8). Players take turns in order until the board is full.",
            blocks: [
                .list([
                    "Players take turns choosing one unoccupied tile.",
                    "Turn order proceeds in a fixed rotation (for example, clockwise).",
                    "You cannot undo a move once the tile is claimed.",
                ], ordered: true),
                .callout(.tip, title: "Finding your footing", text: "Early moves often contest the center and open multiple shape possibilities. The Strategy section below goes deeper."),
            ],
            navLabel: "Setup & turns",
            navDescription: "Board, turns, and valid moves"
        ),
        Section(
            id: "section-gameplay",
            title: "Valid shapes & rules",
            eyebrow: "Gameplay",
            theme: .amber,
            intro: "Points come from Squares and Diamonds. Rectangles and other four-corner shapes that are not axis-aligned squares do not score as Squares.",
            blocks: [
                .subtitle("Squares"),
                .paragraph("A Square uses four occupied tiles at the corners of an axis-aligned square on the grid. Larger squares are worth more (see Scoring)."),
                .demo(RulebookDemos.squares, caption: "Squares align with the grid; area drives base points."),
                .subtitle("Diamonds"),
                .paragraph("A Diamond uses four tiles equidistant around a center point (a diamond orientation on the grid). They score differently from Squares (see Scoring)."),
                .demo(RulebookDemos.diamonds, caption: "Diamonds are judged by their span, not as stretched squares."),
                .subtitle("What does not count"),
                .paragraph("Non-square rectangles (different width and height in grid units) do not count as Squares and earn no points from that shape type."),
                .demo(RulebookDemos.rectangles, caption: "Rectangles are not valid Squares."),
            ],
            navLabel: "Shapes & rules",
            navDescription: "Squares, diamonds, and what does not score"
        ),
        Section(
            id: "section-scoring",
            title: "Scoring system",
            eyebrow: "Points",
            theme: .amber,
            intro: "Squares score their area in points. Diamonds score at twice their area. Your current multiplier applies to the shapes you complete on that turn.",
            blocks: [
                .subtitle("Square point values"),
                .table(caption: "Axis-aligned square size to base points", columns: ("Square size", "Points"), rows: [
                    ("8x8", "64"), ("7x7", "49"), ("6x6", "36"), ("5x5", "25"), ("4x4", "16"), ("3x3", "9"), ("2x2", "4"),
                ]),
                .demo(RulebookDemos.scoringSquares, caption: "Larger squares mean larger base scores before multipliers."),
                .subtitle("Diamond point values"),
                .paragraph("Diamonds are worth two times their area (in the same size sense used by the game rules)."),
                .table(caption: "Diamond size to base points", columns: ("Diamond size", "Points"), rows: [
                    ("4x4", "32"), ("3x3", "18"), ("2x2", "8"),
                ]),
                .demo(RulebookDemos.scoringDiamonds, caption: "Diamond scoring uses the 2x area rule."),
            ],
            navLabel: "Scoring",
            navDescription: "Points for every shape size"
        ),
        Section(
            id: "section-multipliers",
            title: "Multipliers",
            eyebrow: "Bonus scoring",
            theme: .violet,
            intro: "When you complete more than one shape in a single turn, your multiplier can increase. If you stop forming multiple shapes, it resets.",
            blocks: [
                .subtitle("Earning a higher multiplier"),
                .paragraph("When you complete multiple shapes on one move, the multiplier increases based on how many new shapes you formed that turn. Current multiplier plus new shapes minus one gives the new multiplier value."),
                .formula(lines: ["Current mult. + new shapes − 1 = new mult."], caption: "Example: mult 1, two new shapes: 1 + 2 − 1 = 2"),
                .formula(lines: ["2 + 3 − 1 = 4"], caption: "Example: mult 2, three new shapes: new mult. 4"),
                .demo(RulebookDemos.multsGetting, caption: "Multiple shapes in one turn feed the multiplier."),
                .subtitle("Keeping your multiplier"),
                .paragraph("To keep a multiplier above 1, you need to keep completing at least two shapes on your turns. If a turn completes fewer than two shapes, the multiplier resets to 1."),
                .demo(RulebookDemos.multsKeeping, caption: "Letting a turn fall below two shapes resets the chain."),
                .callout(.strategy, title: "Example scoring line", text: "Blue: two 4x4 squares at 16 points each, times multiplier 2, equals 64 points. Red: one 3x3 diamond (18) plus one 3x3 square (9), times multiplier 2, equals 54 points."),
            ],
            navLabel: "Multipliers",
            navDescription: "Build and keep your bonus"
        ),
        Section(
            id: "section-winning",
            title: "Winning the game",
            eyebrow: "Finish",
            theme: .sky,
            intro: "The game ends when all tiles are filled.",
            blocks: [
                .list([
                    "The player with the highest score wins.",
                    "If scores tie, the player who formed the most shapes (squares plus diamonds) wins.",
                    "If those tie, the player with the most diamonds wins.",
                    "If still tied, the game is a draw.",
                ], ordered: true),
            ],
            navLabel: "End of game",
            navDescription: "Ties and victory"
        ),
        Section(
            id: "section-strategies",
            title: "Advanced strategies",
            eyebrow: "Level up",
            theme: .rose,
            intro: "These ideas build on the rules above: create options, stack value, control space, and time your multiplier.",
            blocks: [
                .callout(.tip, title: "How to use this section", text: "Each subsection includes a short explanation and, where helpful, a live example you can watch play out. Skim the headings, then dive into the patterns that match your style."),
            ],
            subsections: [
                Subsection(id: "strategy-shape-options", title: "Shape options", blocks: [
                    .paragraph("Set up positions where your opponent can only block one of several threats, so you still convert points elsewhere. Force trade-offs instead of clean stops."),
                    .subtitle("Example: two open 2x2 diamonds"),
                    .demo(RulebookDemos.shapeOptions1, caption: "Two simultaneous diamond threats."),
                    .subtitle("Example: diamonds plus a square"),
                    .demo(RulebookDemos.shapeOptions2, caption: "Mixing diamond and square pressure."),
                    .subtitle("Example: multiple large squares and a diamond"),
                    .demo(RulebookDemos.shapeOptions3, caption: "High-value overlapping threats."),
                ]),
                Subsection(id: "strategy-shape-stacking", title: "Shape stacking", blocks: [
                    .paragraph("Plan sequences so one turn completes several shapes, feeding your multiplier and total in the same swing."),
                    .subtitle("Stack two 2x2 diamonds"),
                    .demo(RulebookDemos.shapeStacks1, caption: "Two 2x2 diamonds in one move: (8 + 8) × 2 = 32."),
                    .subtitle("Stack two 3x3 squares"),
                    .demo(RulebookDemos.shapeStacks2, caption: "Two 3x3 squares in one move: (9 + 9) × 2 = 36."),
                    .subtitle("Squares plus diamond"),
                    .demo(RulebookDemos.shapeStacks3, caption: "Two 3x3 squares and a 3x3 diamond in one move: (9 + 9 + 18) × 3 = 108."),
                ]),
                Subsection(id: "strategy-board-control", title: "Controlling the board", blocks: [
                    .paragraph("Take tiles that block huge opposing Squares or Diamonds. Avoid leaving holes that become high-value finishes for someone else."),
                ]),
                Subsection(id: "strategy-multiplier", title: "Multiplier mastery", blocks: [
                    .paragraph("When you are ahead, plan turns so you still complete two shapes when it matters. When behind, prioritize turns that spike the multiplier and catch up in one or two swings."),
                ]),
                Subsection(id: "strategy-adaptive", title: "Adaptive play", blocks: [
                    .paragraph("Shift between defense and offense based on score and remaining tiles. Leading players can simplify the position; trailing players may need forced complications."),
                ]),
                Subsection(id: "strategy-opening", title: "Opening moves", blocks: [
                    .list([
                        "Contest central influence so later squares and diamonds stay reachable.",
                        "Seed patterns that can branch into multiple shape types.",
                        "Deny easy large shapes on the first few rotations if your opponent telegraphs them.",
                    ]),
                ]),
                Subsection(id: "strategy-midgame", title: "Mid-game", blocks: [
                    .list([
                        "Start completing medium and large shapes while multipliers are still available.",
                        "Look for one move that completes two or more shapes.",
                        "Block finishes that would swing the game.",
                    ]),
                ]),
                Subsection(id: "strategy-endgame", title: "Endgame", blocks: [
                    .list([
                        "Count remaining tiles and possible shape closures.",
                        "Maximize multiplier turns before the board locks up.",
                        "If ahead, remove opponent outs; if behind, create messy fights for the last clusters.",
                    ]),
                ]),
                Subsection(id: "strategy-summary", title: "Putting it together", blocks: [
                    .paragraph("Strong play mixes spatial reading, tempo, and multiplier timing. Use the sections above as a checklist: shape basics, scoring tables, multiplier rules, then the strategies that fit your matchup."),
                    .callout(.note, title: "You are ready", text: "Take these rules online, pass the device in local play, or challenge the CPU. Consistency comes from reviewing games and spotting one new pattern each time."),
                ]),
            ],
            navLabel: "Strategies",
            navDescription: "Patterns, blocking, and tempo"
        ),
    ]
}
