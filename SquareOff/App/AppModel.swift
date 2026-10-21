import Observation
import SquareOffCore
import SquareOffNet
import SwiftUI

/// What the setup screens hand to a new game.
nonisolated struct GameConfig: Equatable, Codable, Sendable {
    enum Mode: Equatable, Codable, Sendable {
        case cpu(CPULevel)
        case passAndPlay

        private enum CodingKeys: String, CodingKey { case kind, level }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            switch try c.decode(String.self, forKey: .kind) {
            case "cpu": self = .cpu(try c.decode(CPULevel.self, forKey: .level))
            default: self = .passAndPlay
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .cpu(let level):
                try c.encode("cpu", forKey: .kind)
                try c.encode(level, forKey: .level)
            case .passAndPlay:
                try c.encode("local", forKey: .kind)
            }
        }
    }

    var mode: Mode
    var boardSize = 8
    var timerSeconds = 0
    var players: [SetupPlayer]

    var title: String {
        switch mode {
        case .cpu(let level): "vs CPU · Level \(level.number) · \(boardSize)×\(boardSize)"
        case .passAndPlay: "Pass & Play · \(players.count) players · \(boardSize)×\(boardSize)"
        }
    }
}

nonisolated struct SetupPlayer: Equatable, Identifiable, Codable, Sendable {
    let id: Int
    var name: String
    var colorHex: String
}

enum AppTab: Hashable {
    case play, learn, profile
}

@Observable
final class AppModel {
    /// The server stack in use (mock or local docker). Rebuilt by `switchBackend`.
    private(set) var backend: Backend
    let accounts: AccountStore
    let toasts = ToastCenter()
    var account: Account { accounts.account }
    var selectedTab: AppTab = .play
    /// Debug deep links (`-demoScreen`): screens to open once the root view appears.
    var pendingPlayRoute: PlayRoute?
    var pendingSignIn = false
    var pendingRulesSection: String?
    var pendingColorPicker = false
    /// `squareoff://join/<code>` or an invite link: the Online hub joins it when it appears.
    var pendingJoinCode: Int?
    /// `-demoOnline`: the Online hub pushes the waiting room as soon as it appears.
    var pendingOnlineRoom = false
    /// The local game on screen (presented full screen). Kept after it ends so Home can offer "Continue".
    var activeGame: GameSession?
    /// The online game on screen, if any. Takes precedence over `activeGame` in the cover.
    var activeOnlineGame: OnlineGameSession?
    var isGamePresented = false

    /// Lobby state machine for online play; survives backend switches by rebuilding transports lazily.
    @ObservationIgnored private(set) lazy var online: RoomCoordinator = {
        let coordinator = RoomCoordinator(
            makeTransport: { [unowned self] in self.backend.makeOnlineTransport() },
            identityProvider: { [unowned self] in try await self.accounts.ensureIdentity() }
        )
        coordinator.onPlay = { [weak self] session in self?.presentOnline(session) }
        return coordinator
    }()

    /// The unfinished local game on disk; `activeGame` is rebuilt from it at launch.
    let localGames: LocalGameStore

    init(configuration: BackendConfiguration = .load(), localGames: LocalGameStore = LocalGameStore()) {
        let backend = Backend(configuration: configuration)
        self.backend = backend
        self.localGames = localGames
        accounts = AccountStore(backend: backend)
        if let snapshot = localGames.load(),
           let restored = GameSession(restoring: snapshot, cpu: backend.makeCPUProvider(config: snapshot.config, notices: SessionNoticeRelay()), store: localGames),
           !restored.isOver {
            activeGame = restored
        } else {
            localGames.clear()
        }
    }

    /// The Continue card: bring the saved local game back on screen.
    func resumeGame() {
        guard let activeGame, !activeGame.isOver else { return }
        if activeOnlineGame != nil { return }
        isGamePresented = true
    }

    func discardGame() {
        activeGame?.leave()
        activeGame = nil
        localGames.clear()
    }

    /// The header arrow in a local game: back to the menu with the game kept for "Continue".
    func minimizeGame() {
        isGamePresented = false
    }

    /// Where leaving a game lands (web `handleLeave(to)`): Home pops to the root, Setup shows the Play page.
    enum GameExit { case home, setup }
    /// Set by `exitGame`; the root view pops its navigation stack and clears the flag.
    var pendingPopToRoot = false

    func exitGame(to destination: GameExit) {
        isGamePresented = false
        if activeOnlineGame == nil {
            // Leaving a local game forgets it (web `handleLeave` clears the saved game).
            activeGame = nil
            localGames.clear()
        }
        selectedTab = .play
        switch destination {
        case .home:
            pendingPopToRoot = true
        case .setup:
            pendingPlayRoute = .play
        }
    }

    func presentOnline(_ session: OnlineGameSession) {
        activeGame?.stop()
        activeGame = nil
        activeOnlineGame = session
        isGamePresented = true
    }

    /// The full-screen game went away. Online sessions are over at that point (the room was
    /// left or closed); local games stay around for "Continue".
    func gameDismissed() {
        if activeOnlineGame != nil {
            activeOnlineGame = nil
            online.gameEnded()
        }
    }

    func start(_ config: GameConfig) {
        activeGame?.stop()
        if let onlineGame = activeOnlineGame {
            onlineGame.leave()
            activeOnlineGame = nil
            online.gameEnded()
        }
        let notices = SessionNoticeRelay()
        let session = GameSession(
            config: config,
            cpu: backend.makeCPUProvider(config: config, notices: notices),
            recorder: backend.makeRecorder(account: account, notices: notices),
            store: localGames
        )
        notices.session = session
        activeGame = session
        isGamePresented = true
    }

    /// Switches server stacks. A game in progress keeps the providers it was created with.
    func switchBackend(to kind: BackendKind) {
        guard kind != backend.configuration.kind else { return }
        var configuration = kind == .live ? BackendConfiguration.localDocker : .mock
        configuration.cpuMovesFromServer = backend.configuration.cpuMovesFromServer
        apply(configuration)
    }

    func setCPUMovesFromServer(_ enabled: Bool) {
        var configuration = backend.configuration
        configuration.cpuMovesFromServer = enabled
        apply(configuration)
    }

    private func apply(_ configuration: BackendConfiguration) {
        configuration.save()
        backend = Backend(configuration: configuration)
        accounts.attach(backend)
        Task { await accounts.restore() }
    }
}
