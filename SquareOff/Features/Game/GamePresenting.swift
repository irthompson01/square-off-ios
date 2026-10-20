import Observation
import SquareOffCore

/// What a game screen may offer for this session.
struct GameCapabilities: Equatable {
    var canRestart = true
    var isSpectator = false
    var isOnline = false
    var roomCode: Int?
}

/// Online rematches happen in two steps: the host resets the room, then starts the new game.
enum RematchState: Equatable {
    case none
    case hostCanStart
    case waitingForHost
}

/// Everything `GameView` (and its board, strip and sheets) needs from a game, whether it runs on
/// device (`GameSession`) or in an online room (`OnlineGameSession`).
@MainActor
protocol GamePresenting: AnyObject, Observable, Identifiable {
    var title: String { get }
    var timerSeconds: Int { get }
    var game: Game { get }
    var spins: [Cell: SpinEvent] { get }
    var lastMove: MoveResult? { get }
    /// Someone else is deciding (the CPU, or a remote player).
    var isCPUThinking: Bool { get }
    var timeRemaining: Int? { get }
    var notice: String? { get set }
    var hiddenShapeOwners: Set<Int> { get set }
    var isGameOverPresented: Bool { get set }
    var placeCount: Int { get }
    var scoreCount: Int { get }
    var isOver: Bool { get }
    var currentPlayer: PlayerState { get }
    var canTap: Bool { get }
    var visibleShapes: [BoardShape] { get }
    var turnLabel: String { get }
    var winnerHeadline: String { get }
    var capabilities: GameCapabilities { get }
    var rematchState: RematchState { get }
    /// "Reconnecting…" and friends; nil when nothing is wrong.
    var connectionLabel: String? { get }

    /// Idempotent: the game view calls it every time it appears.
    func start() async
    func tap(_ cell: Cell)
    /// Local: a fresh game. Online host: resets the room.
    func restart()
    /// Online host: starts the game after a reset. Local: same as `restart()`.
    func startRematch()
    /// The view went away; pause timers but keep the game.
    func stop()
    /// The player is done with this game.
    func leave()
}
