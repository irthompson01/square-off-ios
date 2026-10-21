import Observation
import SquareOffCore
import SquareOffNet
import SwiftUI

/// What the setup screens hand to a new game.
struct GameConfig: Equatable {
    enum Mode: Equatable {
        case cpu(CPULevel)
        case passAndPlay
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

struct SetupPlayer: Equatable, Identifiable {
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
    var pendingPlayRoute: PlayMode?
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

    init(configuration: BackendConfiguration = .load()) {
        let backend = Backend(configuration: configuration)
        self.backend = backend
        accounts = AccountStore(backend: backend)
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
            recorder: backend.makeRecorder(account: account, notices: notices)
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
