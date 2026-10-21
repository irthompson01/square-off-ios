import SquareOffCore
import SquareOffNet
import SwiftUI

@main
struct SquareOffApp: App {
    @State private var app: AppModel

    init() {
        #if DEBUG
        // `-demoSignedIn`: the mock backend restores the demo account from this token at launch.
        if UserDefaults.standard.bool(forKey: "demoSignedIn") {
            UserDefaults.standard.set("mock:\(MockSquareOffAPI.demoUsername)", forKey: "mockAccessToken")
        }
        // `-demoOnline host|guest|spectator|quickmatch` forces the mock backend with quick bots.
        if UserDefaults.standard.string(forKey: "demoOnline") != nil {
            var rooms = MockRoomServer.Configuration()
            rooms.botJoinDelay = .seconds(1.5)
            rooms.botHostStartDelay = .seconds(1)
            Backend.mockRoomConfiguration = rooms
            _app = State(initialValue: AppModel(configuration: .mock))
            return
        }
        #endif
        _app = State(initialValue: AppModel())
    }

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
    /// `-demoGame cpu|cnn|local4|busy|over`, `-demoScreen rules|setup|color|signin` (`-rulesSection <id>` with
    /// rules), `-demoOnline host|guest|spectator|quickmatch` and `-backend mock|live`.
    private func openDemoGameIfRequested() {
        #if DEBUG
        let players = (1...4).map { SetupPlayer(id: $0, name: "Player \($0)", colorHex: Theme.playerColors[$0 - 1]) }
        switch UserDefaults.standard.string(forKey: "demoScreen") {
        case "rules":
            app.selectedTab = .learn
            app.pendingRulesSection = UserDefaults.standard.string(forKey: "rulesSection")
        case "setup": app.pendingPlayRoute = .play
        case "stats": app.pendingPlayRoute = .stats
        case "profile": app.selectedTab = .profile
        case "color":
            app.pendingPlayRoute = .play
            app.pendingColorPicker = true
        case "signin":
            app.selectedTab = .profile
            app.pendingSignIn = true
        default: break
        }
        if let online = UserDefaults.standard.string(forKey: "demoOnline") {
            app.pendingPlayRoute = .play
            app.pendingOnlineRoom = true
            let roomServer = app.backend.roomServer
            Task {
                switch online {
                case "guest":
                    await roomServer?.seedBotRoom(code: 42424, boardSize: 8, timer: 20, hostLevel: .maxMin)
                    await app.online.join(code: 42424)
                case "spectator":
                    await roomServer?.seedBotMatchInProgress(code: 31313, boardSize: 8, moves: 20)
                    await app.online.join(code: 31313)
                case "quickmatch":
                    await app.online.quickMatch(boardSize: 8, timer: 20)
                default:
                    await app.online.host(boardSize: 8, timer: 20, listPublic: true)
                }
            }
            return
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
        case "cnn":
            // Level 3 against the server's model (needs `-backend live` and the docker stack).
            app.start(GameConfig(mode: .cpu(.cnn), boardSize: 8, timerSeconds: 0, players: [SetupPlayer(id: 1, name: "Player 1", colorHex: Theme.playerColors[0])]))
            app.activeGame?.tap(Cell(row: 3, col: 3))
        default:
            app.start(GameConfig(mode: .cpu(.maxMin), boardSize: 8, timerSeconds: 0, players: [SetupPlayer(id: 1, name: "Player 1", colorHex: Theme.playerColors[0])]))
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
                        .navigationDestination(for: PlayRoute.self) { route in
                            switch route {
                            case .play: PlayView()
                            case .stats: StatsView()
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
            if playPath.isEmpty { playPath.append(route) }
            app.pendingPlayRoute = nil
        }
        .onChange(of: app.pendingPopToRoot) { _, pop in
            guard pop else { return }
            playPath = NavigationPath()
            app.pendingPopToRoot = false
        }
        .tabViewStyle(.sidebarAdaptable)
        .appBackground()
        .overlay(alignment: .bottom) { ToastOverlay(center: app.toasts) }
        .syncsMusic()
        .task { await app.accounts.restore() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { app.activeGame?.saveNow() }
            guard phase == .active else { return }
            Task { await app.accounts.restore() }
            app.activeOnlineGame?.sceneDidBecomeActive()
            app.online.sceneDidBecomeActive()
        }
        .onOpenURL { url in
            if let code = InviteLink.roomCode(from: url) {
                app.pendingJoinCode = code
                app.selectedTab = .play
                app.pendingPlayRoute = .play
            }
        }
        .fullScreenCover(isPresented: $app.isGamePresented, onDismiss: app.gameDismissed) {
            Group {
                if let online = app.activeOnlineGame {
                    GameView(session: online)
                } else if let session = app.activeGame {
                    GameView(session: session)
                }
            }
            .environment(app)
            .overlay(alignment: .bottom) { ToastOverlay(center: app.toasts) }
        }
    }
}

/// `squareoff://join/<code>` and the web's `https://<host>/guest/<code>`.
enum InviteLink {
    static func roomCode(from url: URL) -> Int? {
        let parts = url.pathComponents.filter { $0 != "/" }
        if url.scheme == OAuthCallback.scheme {
            guard url.host() == "join", let last = parts.last else { return nil }
            return Int(last)
        }
        guard let index = parts.firstIndex(of: "guest"), parts.indices.contains(index + 1) else { return nil }
        return Int(parts[index + 1])
    }
}
