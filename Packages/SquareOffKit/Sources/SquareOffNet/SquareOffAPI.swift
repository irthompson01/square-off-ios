import Foundation
import SquareOffCore

/// Whose token a request carries: a signed-in account's, or the device's 30-day guest session
/// (`POST /create_guest`). Every game, CPU, matcher and socket call needs one of the two.
public enum TokenKind: Sendable, Equatable {
    case user
    case guest
}

/// Supplies the bearer token for authenticated requests. The app keeps both tokens in the
/// Keychain (the user's wins while it exists); the mock keeps `mock:<username>` /
/// `mock-guest:<id>` strings in UserDefaults.
public protocol TokenProvider: Sendable {
    func accessToken() -> String?
    /// Which kind `token` is. Only the app's combined store can tell; plain stores hold user tokens.
    func kind(of token: String) -> TokenKind
}

public extension TokenProvider {
    func kind(of token: String) -> TokenKind { .user }
}

/// Mints or renews the guest session after a 401 that says the session is missing or dead.
/// `true` means the failed request is retried once with whatever token the provider now holds.
public typealias SessionRecovery = @Sendable () async -> Bool

/// The server's REST API as the app uses it, mirroring the web's service modules
/// (`hero-client/src/services/{auth,game,model}API.ts`). Screens and services talk to this
/// protocol; `LiveSquareOffAPI` hits the docker server and `MockSquareOffAPI` simulates it.
public protocol SquareOffAPI: Sendable {
    // MARK: authAPI
    /// `GET /cpu_player/{type}`: the CPU definition row. Needs a player session (user or guest).
    func cpuPlayer(_ level: CPULevel) async throws -> CPUPlayerResponse
    func login(_ request: LoginRequest) async throws -> LoginResponse
    /// `POST /register`: creates a pending account; `verification_required` means no token is
    /// issued until the emailed link is opened (409 `already_registered`, 400 `captcha_failed`).
    func register(_ request: RegisterRequest) async throws -> RegisterResponse
    /// `POST /verify-email`: redeems the emailed token (400 `verify_token_invalid` / `_expired`).
    func verifyEmail(token: String) async throws -> VerifyEmailResponse
    /// `POST /verify-email/resend`: always 200, whether or not the address has a pending account.
    func resendVerification(email: String) async throws -> MessageResponse
    func logout() async throws
    /// `true` when the token (or cookie) belongs to a signed-in account: `GET /check-auth`
    /// returns 200 (a guest session gets 401 `account_required`).
    func checkAuth() async throws -> Bool
    /// `POST /create_guest`: mints the device's guest session (or renews it when the current
    /// guest token is sent) and returns its bearer token; 409 `already_signed_in` with a user token.
    func createGuest(_ request: CreateGuestRequest) async throws -> CreateGuestResponse
    func profile() async throws -> ProfileResponse
    func updateProfile(_ request: ProfileUpdateRequest) async throws
    /// `GET /{provider}/login?client=ios` → the URL to open in a web auth session.
    func oauthLoginURL(_ provider: OAuthProvider, client: OAuthClient) async throws -> OAuthLoginResponse
    func appleNativeLogin(_ request: AppleNativeLoginRequest) async throws -> LoginResponse
    /// `POST /account/delete`: tombstones the signed-in account and revokes every session.
    func deleteAccount(_ request: AccountDeleteRequest) async throws -> MessageResponse
    /// `POST /password/forgot`: always succeeds, whether or not the address has an account.
    func requestPasswordReset(email: String) async throws -> MessageResponse
    /// `POST /password/reset`: 400 `reset_token_invalid` / `reset_token_expired`, 422 when short.
    func resetPassword(token: String, newPassword: String) async throws -> MessageResponse

    // MARK: feedbackAPI
    func sendFeedback(_ request: FeedbackRequest) async throws -> FeedbackResponse

    // MARK: gameAPI
    func startGame(_ request: StartGameRequest) async throws -> StartGameResponse
    func insertTurn(gameID: Int, _ turn: GameTurnRequest) async throws -> GameTurnResponse
    /// `PUT /update/players`, sent by an online host right before `GAME_START`.
    func updatePlayers(gameID: Int, players: [PlayerPayload]) async throws
    func endGame(_ request: GameEndRequest) async throws
    func replay(gameID: Int) async throws -> GameReplayPayload

    // MARK: stats (signed-in users only)
    func statsView() async throws -> PlayerStatsView
    func statsViewCPU(boardSize: Int?, timer: Int?, cpuType: String?) async throws -> [PlayerStatsCPUView]
    /// `GET /stats_view_human`: the same summary over games against people only.
    func statsViewHuman(boardSize: Int?, timer: Int?) async throws -> PlayerStatsView
    /// `GET /profile_stats_filters?scope=human|cpu`: the board sizes, timers (and CPU types) with games.
    func profileStatsFilters(scope: String) async throws -> ProfileStatsFilters
    func recentGames(limit: Int, offset: Int) async throws -> RecentGamesPage

    // MARK: modelAPI
    func cpuMove(_ request: CPUMoveRequest) async throws -> CPUMoveResponse
}

public enum APIError: Error, Equatable {
    case http(status: Int, body: String)
    case invalidResponse
    case timeout

    public var isUnauthorized: Bool {
        if case .http(status: 401, _) = self { return true }
        return false
    }

    public var status: Int? {
        if case let .http(status, _) = self { return status }
        return nil
    }

    /// Why the server ended the session, when a 401 says so (never for a failed `/login`,
    /// whose 401 is "Invalid credentials").
    public var sessionEndReason: SessionEndReason? {
        guard status == 401, let detail else { return nil }
        return SessionEndReason(rawValue: detail)
    }

    /// 401 on a player route with no usable session: the client mints a guest and retries.
    public static let sessionRequiredCode = "session_required"
    /// 401 on an account route with a guest token: sign in to continue (never a sign-out).
    public static let accountRequiredCode = "account_required"
    /// 409 from `POST /create_guest` while a user token is attached.
    public static let alreadySignedInCode = "already_signed_in"

    public var isSessionRequired: Bool { status == 401 && detail == Self.sessionRequiredCode }
    public var isAccountRequired: Bool { status == 401 && detail == Self.accountRequiredCode }

    /// FastAPI's `{"detail": "..."}` when the body carries one.
    public var detail: String? {
        guard case let .http(_, body) = self,
              let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let text = object["detail"] as? String { return text }
        if let list = object["detail"] as? [[String: Any]] {
            return list.compactMap { $0["msg"] as? String }.joined(separator: ", ")
        }
        return nil
    }
}

/// The `detail` codes a 401 carries when a session is over (`server/src/auth/session.py`).
/// The web treats all of them as "signed out"; so does the app (`AccountStore.sessionEnded`).
public enum SessionEndReason: String, Sendable, Equatable, CaseIterable {
    case expired = "Token has expired"
    case revoked = "session_revoked"
    case disabled = "account_disabled"
    case userNotFound = "User not found"
    case invalid = "Could not validate credentials"
}

/// Where the server lives. REST routes are under `/api`, the game socket at `/ws`, and the web
/// client (for invite links) at `webOrigin`.
public struct APIEnvironment: Sendable, Equatable {
    public let baseURL: URL
    public let webSocketURL: URL
    public let webOrigin: URL

    public init(baseURL: URL, webSocketURL: URL, webOrigin: URL) {
        self.baseURL = baseURL
        self.webSocketURL = webSocketURL
        self.webOrigin = webOrigin
    }

    /// The docker-compose stack: backend on `https://localhost:8002` (mkcert certificate),
    /// Vite dev client on `https://localhost:5173`.
    public static let local = APIEnvironment(
        baseURL: URL(string: "https://localhost:8002/api")!,
        webSocketURL: URL(string: "wss://localhost:8002/ws")!,
        webOrigin: URL(string: "https://localhost:5173")!
    )

    /// square-off.com: Caddy proxies `/api/*` and `/ws*` to the backend and serves the web
    /// client at the origin (invite links, password-reset links).
    public static let production = APIEnvironment(
        baseURL: URL(string: "https://square-off.com/api")!,
        webSocketURL: URL(string: "wss://square-off.com/ws")!,
        webOrigin: URL(string: "https://square-off.com")!
    )

    /// Standard layout for any host: `https://host:port/api`, `wss://host:port/ws`.
    public static func host(_ host: String, port: Int, secure: Bool = true, webOrigin: URL) -> APIEnvironment {
        let http = secure ? "https" : "http"
        let ws = secure ? "wss" : "ws"
        return APIEnvironment(
            baseURL: URL(string: "\(http)://\(host):\(port)/api")!,
            webSocketURL: URL(string: "\(ws)://\(host):\(port)/ws")!,
            webOrigin: webOrigin
        )
    }
}
