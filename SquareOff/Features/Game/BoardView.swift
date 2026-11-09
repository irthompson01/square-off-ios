import SquareOffCore
import SwiftUI

/// Square board: white tiles that flip to the owner's colour, corner spins when shapes form, and
/// the shape overlay drawn through tile centres (web `DomBoard` + `ShapeOverlay`).
struct BoardView<Session: GamePresenting>: View {
    let session: Session

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let n = session.game.board.size
            let layout = BoardLayout(cell: side / CGFloat(n))

            ZStack(alignment: .topLeading) {
                LastMoveGlow(cell: session.lastMove?.cell, layout: layout)
                VStack(spacing: 0) {
                    ForEach(0..<n, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<n, id: \.self) { col in
                                let cell = Cell(row: row, col: col)
                                let owner = session.game.board[cell]
                                Button { session.tap(cell) } label: {
                                    TileView(
                                        owner: owner,
                                        color: color(for: owner),
                                        isLastMove: session.lastMove?.cell == cell,
                                        spin: session.spins[cell],
                                        tile: layout.tile
                                    )
                                }
                                .buttonStyle(TilePressStyle(pressable: owner == nil && session.canTap))
                                .frame(width: layout.cell, height: layout.cell)
                                .accessibilityLabel(label(for: cell))
                            }
                        }
                    }
                }
                ShapeLayer(
                    history: session.shapeHistory,
                    hidden: session.hiddenShapeOwners,
                    lastMove: session.lastMove,
                    layout: layout,
                    color: { color(for: $0) ?? .white }
                )
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .sensoryFeedback(.impact(weight: .light), trigger: session.placeCount)
        .sensoryFeedback(.success, trigger: session.scoreCount)
    }

    private func color(for owner: Int?) -> Color? {
        guard let owner, let player = session.game.players.first(where: { $0.id == owner }) else { return nil }
        return Color(hex: player.colorHex)
    }

    private func label(for cell: Cell) -> String {
        let owner = session.game.board[cell].flatMap { id in session.game.players.first { $0.id == id }?.name }
        return "Row \(cell.row + 1), column \(cell.col + 1), \(owner ?? "empty")"
    }
}

/// A read-only board (tiles, spins, shape overlay) for the rulebook demos and replays.
struct PlaybackBoardView: View {
    let game: Game
    let spins: [Cell: SpinEvent]
    let lastMove: MoveResult?
    /// Shapes in formation order. Defaults to the game's move list (empty after a rebuild).
    var history: [BoardShape]? = nil

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let n = game.board.size
            let layout = BoardLayout(cell: side / CGFloat(n))
            ZStack(alignment: .topLeading) {
                LastMoveGlow(cell: lastMove?.cell, layout: layout)
                VStack(spacing: 0) {
                    ForEach(0..<n, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<n, id: \.self) { col in
                                let cell = Cell(row: row, col: col)
                                let owner = game.board[cell]
                                TileView(
                                    owner: owner,
                                    color: color(for: owner),
                                    isLastMove: lastMove?.cell == cell,
                                    spin: spins[cell],
                                    tile: layout.tile
                                )
                                .frame(width: layout.cell, height: layout.cell)
                            }
                        }
                    }
                }
                ShapeLayer(
                    history: history ?? game.moves.flatMap(\.newShapes),
                    hidden: [],
                    lastMove: lastMove,
                    layout: layout,
                    color: { color(for: $0) ?? .white }
                )
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func color(for owner: Int?) -> Color? {
        guard let owner, let player = game.players.first(where: { $0.id == owner }) else { return nil }
        return Color(hex: player.colorHex)
    }
}

/// Cell-based geometry: the tile is drawn at 95% of its cell, centred; shape corners sit at
/// cell centres (`board-geometry.ts`).
struct BoardLayout {
    let cell: CGFloat

    var tile: CGFloat { cell * 0.95 }

    func center(of cell: Cell) -> CGPoint {
        CGPoint(x: (CGFloat(cell.col) + 0.5) * self.cell, y: (CGFloat(cell.row) + 0.5) * self.cell)
    }
}

/// Press feedback for an empty, tappable tile (`whileTap={{ scale: 0.92 }}`).
struct TilePressStyle: ButtonStyle {
    let pressable: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(pressable && configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// The white glow behind the last-placed tile. One view under the grid instead of a shadow on
/// every tile; like the CSS box-shadow it shows through the gaps around the tile.
private struct LastMoveGlow: View {
    let cell: Cell?
    let layout: BoardLayout

    var body: some View {
        if let cell {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.8))
                .frame(width: layout.tile, height: layout.tile)
                .shadow(color: .white.opacity(0.8), radius: 15)
                .position(layout.center(of: cell))
        }
    }
}

/// One tile (web `DomTile`). Claiming it flips the white face over to the owner's colour
/// (320 ms, ease-out cubic); forming a shape spins it in-plane by 90° × turns, accumulating.
struct TileView: View {
    let owner: Int?
    let color: Color?
    let isLastMove: Bool
    let spin: SpinEvent?
    let tile: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flip: Double
    @State private var rotation: Double = 0

    init(owner: Int?, color: Color?, isLastMove: Bool, spin: SpinEvent?, tile: CGFloat) {
        self.owner = owner
        self.color = color
        self.isLastMove = isLastMove
        self.spin = spin
        self.tile = tile
        // A tile that is already owned when it appears (rejoin, replay seek) shows its colour at once.
        _flip = State(initialValue: owner == nil ? 0 : 180)
    }

    var body: some View {
        FlipFace(angle: flip, back: color ?? Theme.tileEmpty, isLastMove: isLastMove, flat: reduceMotion)
            .frame(width: tile, height: tile)
            .rotationEffect(.degrees(rotation))
            .onChange(of: owner) { old, new in
                if old == nil, new != nil {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .easeOutCubic(SpinSchedule.flipDuration)) { flip = 180 }
                } else if new == nil {
                    // Board cleared: snap back, no animation.
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        flip = 0
                        rotation = 0
                    }
                }
            }
            .onChange(of: spin) { _, event in
                guard let event, !reduceMotion else { return }
                withAnimation(.easeOutCubic(event.duration).delay(event.delay)) {
                    rotation += event.degrees
                }
            }
    }
}

/// Two-faced tile. `Animatable` so the face swaps at 90° during the flip (a plain `angle < 90`
/// in a body would only see the final value). With `flat` (Reduce Motion) the colour fades in instead.
private struct FlipFace: View, Animatable {
    var angle: Double
    let back: Color
    let isLastMove: Bool
    let flat: Bool

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        ZStack {
            shape.fill(Theme.tileEmpty)
                .overlay(shape.strokeBorder(Theme.tileBorder, lineWidth: 1))
            shape.fill(back)
                .opacity(flat ? angle / 180 : (angle >= 90 ? 1 : 0))
        }
        .overlay {
            if isLastMove { shape.strokeBorder(.white, lineWidth: 4) }
        }
        .rotation3DEffect(.degrees(flat ? 0 : angle), axis: (x: 0, y: 1, z: 0), perspective: 0.25)
    }
}

/// Every formed shape, in formation order, with the web's layering (squares, diamonds, then
/// the shapes being drawn on top), age/density fading and the two-stroke draw-on.
struct ShapeLayer: View {
    let history: [BoardShape]
    let hidden: Set<Int>
    let lastMove: MoveResult?
    let layout: BoardLayout
    let color: (Int) -> Color

    private struct Entry: Identifiable, Equatable {
        let shape: BoardShape
        let order: Int
        let opacity: Double
        let isDrawing: Bool
        var id: String { shape.id }
    }

    var body: some View {
        let visible = history.enumerated().filter { !hidden.contains($0.element.ownerID) }
        let newest = history.count - 1
        let drawing = Set(lastMove?.newShapes.map(\.id) ?? [])
        let entries = visible
            .map { index, shape in
                Entry(
                    shape: shape,
                    order: index,
                    opacity: ShapeAge.opacity(order: index, newest: newest, visibleCount: visible.count),
                    isDrawing: drawing.contains(shape.id)
                )
            }
            .sorted { a, b in
                let ka = (a.shape.kind == .diamond ? 1 : 0, a.order)
                let kb = (b.shape.kind == .diamond ? 1 : 0, b.order)
                return ka < kb
            }
        ZStack(alignment: .topLeading) {
            ForEach(entries) { entry in
                ShapeView(
                    shape: entry.shape,
                    isNew: entry.isDrawing,
                    startCorner: lastMove?.cell,
                    ageOpacity: entry.opacity,
                    lineWidth: max(2, layout.tile * 0.07),
                    color: color(entry.shape.ownerID),
                    layout: layout
                )
                .zIndex(entry.isDrawing ? 1 : 0)
            }
        }
        .allowsHitTesting(false)
    }
}

/// One shape. New shapes draw on from the tapped corner in both directions, meeting at the
/// opposite corner (1.2 s), with the fill fading in after 450 ms. Everything else is static at its
/// age opacity; the draw state is created finished so toggles and re-renders never replay it.
private struct ShapeView: View {
    let shape: BoardShape
    let isNew: Bool
    let startCorner: Cell?
    let ageOpacity: Double
    let lineWidth: CGFloat
    let color: Color
    let layout: BoardLayout

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat
    @State private var strokeShown: Bool
    @State private var fillShown: Bool

    init(shape: BoardShape, isNew: Bool, startCorner: Cell?, ageOpacity: Double, lineWidth: CGFloat, color: Color, layout: BoardLayout) {
        self.shape = shape
        self.isNew = isNew
        self.startCorner = startCorner
        self.ageOpacity = ageOpacity
        self.lineWidth = lineWidth
        self.color = color
        self.layout = layout
        _progress = State(initialValue: isNew ? 0 : 1)
        _strokeShown = State(initialValue: !isNew)
        _fillShown = State(initialValue: !isNew)
    }

    var body: some View {
        let closed = Self.outline(shape, layout: layout)
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        let strokeColor = color.mix(with: .white, by: 0.45)
        ZStack(alignment: .topLeading) {
            closed.fill(color.opacity(0.13)).opacity(fillShown ? 1 : 0)
            if progress < 1 {
                let (clockwise, counter) = Self.halves(shape, from: startCorner, layout: layout)
                clockwise.trim(from: 0, to: progress).stroke(strokeColor, style: style)
                counter.trim(from: 0, to: progress).stroke(strokeColor, style: style)
            } else {
                closed.stroke(strokeColor, style: style)
            }
        }
        .opacity(ageOpacity * (strokeShown ? 1 : 0))
        .animation(.easeOut(duration: 0.3), value: ageOpacity)
        .onAppear {
            guard progress < 1 else { return }
            if reduceMotion {
                progress = 1
                strokeShown = true
                fillShown = true
                return
            }
            withAnimation(.easeOut(duration: 0.05)) { strokeShown = true }
            withAnimation(.easeOutCubic(1.2)) { progress = 1 }
            withAnimation(.easeOut(duration: 0.5).delay(0.45)) { fillShown = true }
        }
    }

    static func outline(_ shape: BoardShape, layout: BoardLayout) -> Path {
        var path = Path()
        path.addLines(shape.corners.map(layout.center(of:)))
        path.closeSubpath()
        return path
    }

    /// Two open polylines from the start corner (the tapped cell if it is a corner, else the
    /// nearest corner by Manhattan distance), one each way round, each half the perimeter.
    static func halves(_ shape: BoardShape, from tapped: Cell?, layout: BoardLayout) -> (Path, Path) {
        let corners = shape.corners
        let start: Int
        if let tapped {
            start = corners.indices.min { manhattan(corners[$0], tapped) < manhattan(corners[$1], tapped) } ?? 0
        } else {
            start = 0
        }
        let point = { (i: Int) in layout.center(of: corners[((i % 4) + 4) % 4]) }
        var clockwise = Path()
        clockwise.addLines([point(start), point(start + 1), point(start + 2)])
        var counter = Path()
        counter.addLines([point(start), point(start - 1), point(start - 2)])
        return (clockwise, counter)
    }

    private static func manhattan(_ a: Cell, _ b: Cell) -> Int {
        abs(a.row - b.row) + abs(a.col - b.col)
    }
}
