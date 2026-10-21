import SquareOffCore
import SwiftUI

/// Navigation targets pushed on the Play tab.
enum PlayRoute: Hashable {
    /// The Play page in Vs Computer mode.
    case play
    /// The Play page opened on Online › Quick match.
    case online
    case stats
}

/// Home: the logo and title, Start Game / Online Match, the Continue card when a local game is
/// saved, and a board that plays itself underneath.
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                hero.padding(.top, sizeClass == .regular ? 48 : 28).padding(.bottom, 14)
                Button { app.pendingPlayRoute = .play } label: {
                    Label("Start Game", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle(large: true))
                Button { app.pendingPlayRoute = .online } label: {
                    Label("Online Match", systemImage: "globe")
                }
                .buttonStyle(SecondaryButtonStyle())
                if let session = app.activeGame, !session.isOver {
                    ContinueGameCard(session: session).padding(.top, 6)
                }
                BoardShowcase()
                    .frame(maxWidth: sizeClass == .regular ? 420 : 320)
                    .padding(.top, 18)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .appBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var hero: some View {
        VStack(spacing: 14) {
            LogoMark().frame(width: 72, height: 72)
            Text("SQUARE OFF")
                .font(.system(size: 40, weight: .black).width(.expanded))
                .foregroundStyle(Theme.foreground)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Text("A Strategic Battle of Shapes")
                .font(.subheadline)
                .foregroundStyle(Theme.foregroundSecondary)
        }
    }
}

/// A 6×6 game between two CPUs that plays itself under the Home buttons, with the real flips,
/// spins and shape draw-on, then starts over. Decorative: no taps, hidden from VoiceOver, and
/// paused whenever Home is covered or the app is in the background.
struct BoardShowcase: View {
    static let size = 6
    private static let players = [
        PlayerState(id: 1, name: "Blue", colorHex: Theme.playerColors[0]),
        PlayerState(id: 2, name: "Red", colorHex: Theme.playerColors[1]),
    ]

    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var game = Game(boardSize: BoardShowcase.size, players: BoardShowcase.players)
    @State private var spins: [Cell: SpinEvent] = [:]
    @State private var lastMove: MoveResult?
    @State private var sequence = 0
    @State private var isVisible = false

    private var isRunning: Bool { isVisible && scenePhase == .active && !app.isGamePresented }

    var body: some View {
        PlaybackBoardView(game: game, spins: spins, lastMove: lastMove)
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
            .task(id: isRunning) {
                guard isRunning else { return }
                await play()
            }
            .accessibilityHidden(true)
    }

    private func play() async {
        while !Task.isCancelled {
            if game.isOver {
                try? await Task.sleep(for: .seconds(2.5))
                guard !Task.isCancelled else { return }
                reset()
            }
            try? await Task.sleep(for: .milliseconds(lastMove?.newShapeCount ?? 0 > 0 ? 1600 : 800))
            guard !Task.isCancelled else { return }
            step()
        }
    }

    private func step() {
        // A sharp player against a looser one keeps the board lively and full of shapes.
        let strategy: CPUStrategy = game.currentPlayer.id == 1 ? .maxMinOptimal : .maxRandom
        let cell = strategy.chooseMove(in: game)
        guard let result = try? game.place(at: cell) else { return }
        sequence += 1
        for (tile, event) in SpinSchedule.events(for: result, sequence: sequence, continuousIndex: false) {
            spins[tile] = event
        }
        lastMove = result
    }

    private func reset() {
        game = Game(boardSize: Self.size, players: Self.players)
        spins = [:]
        lastMove = nil
    }
}

/// Four coloured tiles joined by a square outline.
struct LogoMark: View {
    var body: some View {
        GeometryReader { proxy in
            let s = proxy.size.width
            let tile = s * 0.36
            ZStack {
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: tile * 0.23, style: .continuous)
                        .fill(Color(hex: Theme.playerColors[i]))
                        .frame(width: tile, height: tile)
                        .position(x: i % 2 == 0 ? tile / 2 + s * 0.05 : s - tile / 2 - s * 0.05,
                                  y: i < 2 ? tile / 2 + s * 0.05 : s - tile / 2 - s * 0.05)
                }
                Rectangle()
                    .stroke(.white, lineWidth: 2.5)
                    .frame(width: s - tile - s * 0.1, height: s - tile - s * 0.1)
            }
        }
        .accessibilityHidden(true)
    }
}
