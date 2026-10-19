import Observation
import SquareOffCore
import SquareOffNet
import SwiftUI

/// Which server the app talks to. Mock by default so the app runs with no backend.
enum Backend: String, CaseIterable, Identifiable {
    case mock
    case local

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mock: "Mock (offline)"
        case .local: "Local server"
        }
    }
}

enum Account: Equatable {
    case guest
    case signedIn(username: String)

    var displayName: String {
        switch self {
        case .guest: "Guest"
        case .signedIn(let username): username
        }
    }
}

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

@Observable
final class AppModel {
    var backend: Backend {
        didSet {
            UserDefaults.standard.set(backend.rawValue, forKey: "backend")
            api = Self.makeAPI(backend)
        }
    }

    private(set) var api: any SquareOffAPI
    var account: Account = .guest
    /// The game on screen (presented full screen). Kept after it ends so Home can offer "Continue".
    var activeGame: GameSession?
    var isGamePresented = false

    init() {
        let backend = Backend(rawValue: UserDefaults.standard.string(forKey: "backend") ?? "") ?? .mock
        self.backend = backend
        self.api = Self.makeAPI(backend)
    }

    private static func makeAPI(_ backend: Backend) -> any SquareOffAPI {
        switch backend {
        case .mock: MockSquareOffAPI()
        case .local: LiveSquareOffAPI(environment: .local)
        }
    }

    func start(_ config: GameConfig) {
        activeGame = GameSession(config: config, api: api, account: account)
        isGamePresented = true
    }

    func signIn(username: String, password: String) async throws {
        try await api.login(LoginRequest(emailOrUsername: username, password: password))
        account = .signedIn(username: username)
    }

    func signOut() async {
        try? await api.logout()
        account = .guest
    }
}
