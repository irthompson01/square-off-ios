import SquareOffCore
import SquareOffNet
import SwiftUI

@main
struct SquareOffApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(.dark)
                .tint(Theme.link)
                .onAppear(perform: openDemoGameIfRequested)
        }
    }

    /// Debug launch arguments for screenshots / quick iteration:
    /// `-demoGame cpu|local4|busy|over`, `-demoScreen rules|setup|color|signin` (`-rulesSection <id>` with
    /// rules) and `-backend mock|live` (read by `BackendConfiguration.load`).
    private func openDemoGameIfRequested() {
        #if DEBUG
        let players = (1...4).map { SetupPlayer(id: $0, name: "Player \($0)", colorHex: Theme.playerColors[$0 - 1]) }
        switch UserDefaults.standard.string(forKey: "demoScreen") {
        case "rules":
            app.selectedTab = .learn
            app.pendingRulesSection = UserDefaults.standard.string(forKey: "rulesSection")
        case "setup": app.pendingPlayRoute = .cpu
        case "color":
            app.pendingPlayRoute = .cpu
            app.pendingColorPicker = true
        case "signin":
            app.selectedTab = .profile
            app.pendingSignIn = true
        default: break
        }
        guard let kind = UserDefaults.standard.string(forKey: "demoGame"), app.activeGame == nil else { return }
        switch kind {
        case "local4":
            app.start(GameConfig(mode: .passAndPlay, boardSize: 8, timerSeconds: 20, players: players))
        case "busy":
            // A 12×12 Pass & Play game played most of the way by two CPUs: lots of overlapping shapes.
            app.start(GameConfig(mode: .passAndPlay, boardSize: 12, timerSeconds: 0, players: Array(players.prefix(2))))
            if let session = app.activeGame {
                while session.game.moves.count < 126 {
                    session.tap(CPUStrategy.maxMinOptimal.chooseMove(in: session.game))
                }
            }
        case "over":
            // A finished 2×2 Pass & Play game, for the end-of-game screens.
            app.start(GameConfig(mode: .passAndPlay, boardSize: 2, timerSeconds: 0, players: Array(players.prefix(2))))
            for cell in [Cell(row: 0, col: 0), Cell(row: 1, col: 1), Cell(row: 0, col: 1), Cell(row: 1, col: 0)] {
                app.activeGame?.tap(cell)
            }
        default:
            app.start(GameConfig(mode: .cpu(.maxMin), boardSize: 8, timerSeconds: 0, players: [SetupPlayer(id: 1, name: "You", colorHex: Theme.playerColors[0])]))
        }
        #endif
    }
}

/// Play · Learn · Profile. On iPad the tab bar sits at the top and can expand into a sidebar.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var playPath = NavigationPath()

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selectedTab) {
            Tab("Play", systemImage: "square.grid.2x2", value: AppTab.play) {
                NavigationStack(path: $playPath) {
                    HomeView()
                        .navigationDestination(for: PlayMode.self) { mode in
                            switch mode {
                            case .cpu: SetupForm(kind: .cpu)
                            case .passAndPlay: SetupForm(kind: .passAndPlay)
                            case .online: OnlineHubView()
                            }
                        }
                }
            }
            Tab("Learn", systemImage: "book", value: AppTab.learn) {
                NavigationStack { RulesView() }
            }
            Tab("Profile", systemImage: "person", value: AppTab.profile) {
                NavigationStack { ProfileView() }
            }
        }
        .onChange(of: app.pendingPlayRoute, initial: true) { _, route in
            guard let route else { return }
            playPath.append(route)
            app.pendingPlayRoute = nil
        }
        .tabViewStyle(.sidebarAdaptable)
        .appBackground()
        .task { await app.accounts.restore() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await app.accounts.restore() }
        }
        .fullScreenCover(isPresented: $app.isGamePresented) {
            if let session = app.activeGame {
                GameView(session: session)
                    .environment(app)
            }
        }
    }
}
