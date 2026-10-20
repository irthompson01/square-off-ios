import SquareOffCore
import SwiftUI

/// A mini board that plays a `RulebookDemo` on a loop with the real rules, tile spins and shape
/// panes. Playback runs only while the view is on screen; tap to restart.
struct DemoBoardView: View {
    let demo: RulebookDemo

    @State private var game: Game
    @State private var spins: [Cell: SpinEvent] = [:]
    @State private var lastMove: MoveResult?
    @State private var note = ""
    @State private var played = 0
    @State private var run = 0
    @State private var spinSequence = 0

    private static let stepDelay: Duration = .milliseconds(750)
    private static let holdDelay: Duration = .seconds(3)

    init(demo: RulebookDemo) {
        self.demo = demo
        _game = State(initialValue: Self.freshGame(size: demo.size))
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(game.players) { player in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3).fill(Color(hex: player.colorHex)).frame(width: 10, height: 10)
                        Text(player.name).font(.caption.weight(.semibold))
                        Text("\(player.score)").font(.caption.weight(.bold)).monospacedDigit()
                            .contentTransition(.numericText(value: Double(player.score)))
                        if player.multiplier > 1 {
                            Text("×\(player.multiplier)").font(.caption2.weight(.bold)).foregroundStyle(Theme.warning)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Theme.surfaceRaised, in: Capsule())
                    .overlay(Capsule().strokeBorder(player.id == game.currentPlayer.id && played < demo.moves.count ? Color(hex: player.colorHex) : .clear))
                }
                Spacer()
                Text("\(min(played, demo.moves.count))/\(demo.moves.count)")
                    .font(.caption2).monospacedDigit().foregroundStyle(Theme.textSecondary)
            }
            .animation(.easeOut(duration: 0.25), value: played)

            board
                .frame(maxWidth: 320)
                .frame(maxWidth: .infinity)

            Text(note.isEmpty ? " " : note)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .top)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.2), value: note)
        }
        .padding(12)
        .background(Theme.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { run += 1 }
        .task(id: run) { await play() }
        .accessibilityElement(children: .combine)
    }

    private var board: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 3
            let side = min(proxy.size.width, proxy.size.height)
            let n = game.board.size
            let tile = (side - gap * CGFloat(n - 1)) / CGFloat(n)
            let layout = BoardLayout(tile: tile, gap: gap)
            ZStack(alignment: .topLeading) {
                VStack(spacing: gap) {
                    ForEach(0..<n, id: \.self) { row in
                        HStack(spacing: gap) {
                            ForEach(0..<n, id: \.self) { col in
                                let cell = Cell(row: row, col: col)
                                TileView(
                                    color: color(for: game.board[cell]),
                                    isLastMove: lastMove?.cell == cell,
                                    spin: spins[cell],
                                    cornerRadius: tile * 0.17
                                )
                                .frame(width: tile, height: tile)
                            }
                        }
                    }
                }
                ShapeLayer(
                    shapes: game.moves.flatMap(\.newShapes),
                    layout: layout,
                    startCorner: lastMove?.cell,
                    color: { color(for: $0) ?? .white }
                )
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func color(for owner: Int?) -> Color? {
        guard let owner, let player = game.players.first(where: { $0.id == owner }) else { return nil }
        return Color(hex: player.colorHex)
    }

    private func play() async {
        reset()
        while !Task.isCancelled {
            for move in demo.moves {
                try? await Task.sleep(for: Self.stepDelay)
                guard !Task.isCancelled else { return }
                apply(move)
            }
            try? await Task.sleep(for: Self.holdDelay)
            guard !Task.isCancelled else { return }
            reset()
        }
    }

    private func reset() {
        game = Self.freshGame(size: demo.size)
        spins = [:]
        lastMove = nil
        note = ""
        played = 0
    }

    private func apply(_ move: RulebookDemo.Move) {
        let mover = game.currentPlayer
        guard let result = try? game.place(at: Cell(row: move.row, col: move.col)) else { return }
        spinSequence += 1
        for (tile, turns) in result.spinTurns {
            spins[tile] = SpinEvent(id: spinSequence, turns: turns)
        }
        lastMove = result
        played += 1
        note = move.note ?? Self.describe(result, by: mover)
    }

    private static func describe(_ result: MoveResult, by player: PlayerState) -> String {
        guard result.newShapeCount > 0 else { return "\(player.name) claims a tile" }
        let names = result.newShapes.map { "\($0.size)×\($0.size) \($0.kind.rawValue)" }.joined(separator: " + ")
        return "\(player.name): \(names), +\(result.scoreIncrease)"
    }

    private static func freshGame(size: Int) -> Game {
        Game(boardSize: size, players: [
            PlayerState(id: 1, name: "Blue", colorHex: Theme.playerColors[0]),
            PlayerState(id: 2, name: "Red", colorHex: Theme.playerColors[1]),
        ])
    }
}
