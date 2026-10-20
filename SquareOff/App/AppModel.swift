import Observation
import SquareOffCore
import SquareOffNet
import SwiftUI

/// What the setup screens hand to a new game.
struct GameConfig: Equatable {
    enum Mode: Equatable {
        case cpu(CPULevel)
        case passAndPlay
        case onlineMock
    }

    var mode: Mode
    var boardSize = 8
    var timerSeconds = 0
    var players: [SetupPlayer]

    var title: String {
        switch mode {
        case .cpu(let level): "vs CPU · Level \(level.number) · \(boardSize)×\(boardSize)"
        case .passAndPlay: "Pass & Play · \(players.count) players · \(boardSize)×\(boardSize)"
        case .onlineMock: "Online (mock) · \(boardSize)×\(boardSize)"
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
    var account: Account { accounts.account }
    var selectedTab: AppTab = .play
    /// Debug deep links (`-demoScreen`): screens to open once the root view appears.
    var pendingPlayRoute: PlayMode?
    var pendingSignIn = false
    var pendingRulesSection: String?
    var pendingColorPicker = false
    /// The game on screen (presented full screen). Kept after it ends so Home can offer "Continue".
    var activeGame: GameSession?
    var isGamePresented = false

    init(configuration: BackendConfiguration = .load()) {
        let backend = Backend(configuration: configuration)
        self.backend = backend
        accounts = AccountStore(backend: backend)
    }

    func start(_ config: GameConfig) {
        activeGame?.stop()
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
