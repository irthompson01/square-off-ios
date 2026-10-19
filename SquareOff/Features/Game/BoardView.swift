import SquareOffCore
import SwiftUI

/// Square board: tiles plus the shape overlay (outline + translucent fill in the owner's colour).
struct BoardView: View {
    let session: GameSession
    var gap: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let n = session.game.board.size
            let tile = (side - gap * CGFloat(n - 1)) / CGFloat(n)
            let layout = BoardLayout(tile: tile, gap: gap)

            ZStack(alignment: .topLeading) {
                VStack(spacing: gap) {
                    ForEach(0..<n, id: \.self) { row in
                        HStack(spacing: gap) {
                            ForEach(0..<n, id: \.self) { col in
                                let cell = Cell(row: row, col: col)
                                TileView(
                                    color: color(for: session.game.board[cell]),
                                    isLastMove: session.lastMove?.cell == cell,
                                    spin: session.spins[cell],
                                    cornerRadius: tile * 0.17
                                )
                                .frame(width: tile, height: tile)
                                .contentShape(Rectangle().inset(by: -gap / 2))
                                .onTapGesture { session.tap(cell) }
                                .accessibilityElement()
                                .accessibilityLabel(label(for: cell))
                                .accessibilityAddTraits(.isButton)
                            }
                        }
                    }
                }

                ForEach(session.visibleShapes) { shape in
                    ShapeOverlay(
                        shape: shape,
                        color: color(for: shape.ownerID) ?? .white,
                        layout: layout,
                        startCorner: session.lastMove?.cell
                    )
                }
                .allowsHitTesting(false)
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

struct BoardLayout {
    let tile: CGFloat
    let gap: CGFloat

    func center(of cell: Cell) -> CGPoint {
        CGPoint(
            x: CGFloat(cell.col) * (tile + gap) + tile / 2,
            y: CGFloat(cell.row) * (tile + gap) + tile / 2
        )
    }
}

/// One tile. Spins are cumulative (never reset to 0) so there's no snap-back frame, using the
/// web's timing: 360ms per turn, ease-out cubic (`1 − (1 − t)³`).
struct TileView: View {
    let color: Color?
    let isLastMove: Bool
    let spin: SpinEvent?
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation: Double = 0
    @State private var pop: CGFloat = 1

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(color ?? Theme.tileEmpty)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(isLastMove ? Color.white : Color.white.opacity(color == nil ? 0.05 : 0), lineWidth: isLastMove ? 2.5 : 1)
            }
            .rotationEffect(.degrees(rotation))
            .scaleEffect(pop)
            .onChange(of: spin) { _, event in
                guard let event else { return }
                if reduceMotion {
                    pop = 0.85
                    withAnimation(.easeOut(duration: 0.2)) { pop = 1 }
                } else {
                    withAnimation(.timingCurve(0.215, 0.61, 0.355, 1, duration: 0.36 * Double(event.turns))) {
                        rotation += 360 * Double(event.turns)
                    }
                }
            }
    }
}

/// Outline + translucent pane for a formed shape. New shapes draw their outline starting from
/// the tapped corner, and the pane fades in as the corner spins settle.
struct ShapeOverlay: View {
    let shape: BoardShape
    let color: Color
    let layout: BoardLayout
    let startCorner: Cell?

    @State private var progress: CGFloat = 0
    @State private var fill: Double = 0

    var body: some View {
        let path = outline()
        ZStack {
            path.fill(color.opacity(0.13 * fill))
            path.trim(from: 0, to: progress)
                .stroke(color.mix(with: .white, by: 0.45), style: StrokeStyle(lineWidth: max(2.5, layout.tile * 0.07), lineCap: .round, lineJoin: .round))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).delay(0.3)) { progress = 1 }
            withAnimation(.easeOut(duration: 0.5).delay(0.6)) { fill = 1 }
        }
    }

    private func outline() -> Path {
        var corners = shape.corners
        if let start = startCorner, let index = corners.firstIndex(of: start) {
            corners = Array(corners[index...] + corners[..<index])
        }
        var path = Path()
        path.addLines(corners.map(layout.center(of:)))
        path.closeSubpath()
        return path
    }
}
