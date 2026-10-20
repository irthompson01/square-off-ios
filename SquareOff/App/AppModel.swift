import Observation
import SquareOffCore
import SwiftUI

/// Who is playing. v1 is guest-only; `signedIn` is the seam for a later accounts pass.
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

enum AppTab: Hashable {
    case play, learn, profile
}

@Observable
final class AppModel {
    var account: Account = .guest
    var selectedTab: AppTab = .play
    /// Debug deep links (`-demoScreen`): screens to open once the root view appears.
    var pendingPlayRoute: PlayMode?
    var pendingSignIn = false
    var pendingRulesSection: String?
    var pendingColorPicker = false
    /// The game on screen (presented full screen). Kept after it ends so Home can offer "Continue".
    var activeGame: GameSession?
    var isGamePresented = false

    func start(_ config: GameConfig) {
        activeGame?.stop()
        activeGame = GameSession(config: config)
        isGamePresented = true
    }
}
