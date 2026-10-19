import Foundation
import SquareOffCore

/// The subset of the server's REST API the v1 app uses, mirroring the web's service modules.
/// The app talks to this protocol so screens can run against `MockSquareOffAPI` until each
/// flow is wired to `LiveSquareOffAPI`.
public protocol SquareOffAPI: Sendable {
    // authAPI
    func guests() async throws -> GuestsResponse
    func cpuPlayer(_ level: CPULevel) async throws -> CPUPlayerResponse
    func login(_ request: LoginRequest) async throws
    func register(_ request: RegisterRequest) async throws
    func logout() async throws
    /// `true` when the session cookie is valid (`GET /check-auth` returns 200).
    func checkAuth() async throws -> Bool

    // gameAPI
    func startGame(_ request: StartGameRequest) async throws -> StartGameResponse
    func insertTurn(gameID: Int, _ turn: GameTurnRequest) async throws -> GameTurnResponse

    // modelAPI
    func cpuMove(_ request: CPUMoveRequest) async throws -> CPUMoveResponse
}

public enum APIError: Error, Equatable {
    case http(status: Int, body: String)
    case invalidResponse
}

public struct APIEnvironment: Sendable, Equatable {
    public let baseURL: URL

    public init(baseURL: URL) {
        self.baseURL = baseURL
    }

    /// The docker-compose backend (`https://localhost:8002`, mkcert certificate). All routes live under `/api`.
    public static let local = APIEnvironment(baseURL: URL(string: "https://localhost:8002/api")!)
}
