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

    /// Debug launch argument for screenshots / quick iteration: `-demoGame cpu|local4`.
    private func openDemoGameIfRequested() {
        #if DEBUG
        guard let kind = UserDefaults.standard.string(forKey: "demoGame"), app.activeGame == nil else { return }
        let players = (1...4).map { SetupPlayer(id: $0, name: "Player \($0)", colorHex: Theme.playerColors[$0 - 1]) }
        switch kind {
        case "local4":
            app.start(GameConfig(mode: .passAndPlay, boardSize: 8, timerSeconds: 20, players: players))
        default:
            app.start(GameConfig(mode: .cpu(.maxMin), boardSize: 8, timerSeconds: 0, players: [SetupPlayer(id: 1, name: "You", colorHex: Theme.playerColors[0])]))
        }
        #endif
    }
}

/// Play · Learn · Profile. On iPad the tab bar sits at the top and can expand into a sidebar.
struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        TabView {
            Tab("Play", systemImage: "square.grid.2x2") {
                NavigationStack { HomeView() }
            }
            Tab("Learn", systemImage: "book") {
                NavigationStack { RulesView() }
            }
            Tab("Profile", systemImage: "person") {
                NavigationStack { ProfileView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .background(Theme.background)
        .fullScreenCover(isPresented: $app.isGamePresented) {
            if let session = app.activeGame {
                GameView(session: session)
                    .environment(app)
            }
        }
    }
}
