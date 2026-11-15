import SquareOffCore
import SwiftUI

/// A self-playing example board for the rulebook (web `DemoBoard`): the scenario's setup tiles
/// appear at once, then the moves play about one per second on the real rules engine, with the
/// same flips, spins and shape draw-on as a game. Loops; plays only while enabled and on screen.
struct DemoBoardView: View {
    let demo: RulebookDemo
    /// False while the owning section is collapsed: no timers, no playback.
    var enabled = true

    @State private var game: Game
    @State private var spins: [Cell: SpinEvent] = [:]
    @State private var lastMove: MoveResult?
    @State private var caption = DemoBoardView.openingCaption
    @State private var visible = false
    @State private var run = 0
    @State private var spinSequence = 0

    private static let openingCaption = "Blue and Red take turns placing tiles."
    private static let stepDelay: Duration = .milliseconds(1100)
    private static let scoringDelay: Duration = .milliseconds(2000)
    private static let holdDelay: Duration = .milliseconds(3200)

    init(demo: RulebookDemo, enabled: Bool = true) {
        self.demo = demo
        self.enabled = enabled
        _game = State(initialValue: Self.initialGame(demo))
    }

    var body: some View {
        VStack(spacing: 10) {
            PlaybackBoardView(game: game, spins: spins, lastMove: lastMove)
                .padding(8)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(maxWidth: 320)
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(game.players) { player in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 3).fill(Color(hex: player.colorHex)).frame(width: 12, height: 12)
                            Text(player.name).font(.caption.weight(.semibold)).foregroundStyle(Theme.foreground)
                            Text("\(player.score)")
                                .font(Theme.display(13, relativeTo: .caption))
                                .monospacedDigit()
                                .foregroundStyle(Theme.foreground)
                                .contentTransition(.numericText(value: Double(player.score)))
                            Text("×\(player.multiplier)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Theme.foregroundSecondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.white.opacity(0.1), in: Capsule())
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.border))
                        .animation(.easeOut(duration: 0.25), value: player.score)
                    }
                }
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(Theme.foregroundSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .top)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.2), value: caption)
            }
            .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { run += 1 }
        .onScrollVisibilityChange(threshold: 0.35) { visible = $0 }
        .task(id: "\(run)-\(enabled && visible)") {
            guard enabled, visible else { return }
            await play()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Example: \(demo.id)")
    }

    private func play() async {
        reset()
        while !Task.isCancelled {
            for move in demo.moves {
                try? await Task.sleep(for: Self.stepDelay)
                guard !Task.isCancelled else { return }
                let scored = apply(move)
                if scored {
                    try? await Task.sleep(for: Self.scoringDelay - Self.stepDelay)
                    guard !Task.isCancelled else { return }
                }
            }
            try? await Task.sleep(for: Self.holdDelay)
            guard !Task.isCancelled else { return }
            reset()
        }
    }

    private func reset() {
        game = Self.initialGame(demo)
        spins = [:]
        lastMove = nil
        caption = Self.openingCaption
    }

    /// Plays one move; returns whether it scored (the web pauses longer after those).
    private func apply(_ move: RulebookDemo.Move) -> Bool {
        let mover = game.players.first { $0.id == move.player } ?? game.currentPlayer
        guard let result = try? game.place(at: move.cell, by: move.player) else { return false }
        spinSequence += 1
        for (tile, event) in SpinSchedule.events(for: result, sequence: spinSequence, continuousIndex: false) {
            spins[tile] = event
        }
        lastMove = result
        caption = move.note ?? Self.describe(result, by: mover)
        return result.newShapeCount > 0
    }

    /// The web's auto captions (`playMove` in `demo-board.tsx`).
    static func describe(_ result: MoveResult, by mover: PlayerState) -> String {
        let shapes = result.newShapes
        if shapes.isEmpty {
            return mover.multiplier > 1 ? "\(mover.name) forms no shape, so the multiplier resets to ×1" : "\(mover.name) places a tile"
        }
        if shapes.count == 1 {
            return "\(mover.name) completes a \(describe(shapes[0])): +\(result.scoreIncrease)"
        }
        let parts = shapes.map { "a \(describe($0))" }
        let list = parts.dropLast().joined(separator: ", ") + " and " + parts.last!
        let points = shapes.map { String($0.points) }.joined(separator: " + ")
        return "\(mover.name) completes \(list) at once: (\(points)) × \(result.multiplierAfter) = \(result.scoreIncrease)"
    }

    private static func describe(_ shape: BoardShape) -> String {
        "\(shape.size)×\(shape.size) \(shape.kind.rawValue)"
    }

    /// Setup tiles go through the engine (scored, like the web) with nothing animated.
    static func initialGame(_ demo: RulebookDemo) -> Game {
        var game = Game(boardSize: demo.size, players: RulebookDemo.players)
        for placement in demo.setup {
            _ = try? game.place(at: placement.cell, by: placement.player)
        }
        return game
    }
}
