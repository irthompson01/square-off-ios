import Foundation
import SquareOffCore

/// URLSession client for the FastAPI server. Authenticated routes get `Authorization: Bearer`
/// from the `TokenProvider`; the app's session has cookies disabled so nothing else leaks in.
public struct LiveSquareOffAPI: SquareOffAPI {
    private let client: RESTClient

    public init(environment: APIEnvironment, session: URLSession = .shared, tokenProvider: (any TokenProvider)? = nil,
                onSessionEnded: (@Sendable (SessionEndReason) -> Void)? = nil) {
        client = RESTClient(baseURL: environment.baseURL, session: session, tokenProvider: tokenProvider,
                            onSessionEnded: onSessionEnded)
    }

    // MARK: auth

    public func guests() async throws -> GuestsResponse {
        try await client.send("GET", "guests")
    }

    public func cpuPlayer(_ level: CPULevel) async throws -> CPUPlayerResponse {
        try await client.send("GET", "cpu_player/\(level.cpuType)")
    }

    public func login(_ request: LoginRequest) async throws -> LoginResponse {
        // `client=ios` asks for the mobile token lifetime (JWT_MOBILE_TOKEN_EXPIRE_MINUTES).
        try await client.send("POST", "login", query: [URLQueryItem(name: "client", value: OAuthClient.ios.rawValue)], body: request)
    }

    public func register(_ request: RegisterRequest) async throws -> RegisterResponse {
        try await client.send("POST", "register", body: request)
    }

    public func logout() async throws {
        try await client.data("POST", "logout")
    }

    public func checkAuth() async throws -> Bool {
        do {
            try await client.data("GET", "check-auth")
            return true
        } catch let error as APIError where error.isUnauthorized {
            return false
        }
    }

    public func createGuest(_ request: CreateGuestRequest) async throws -> CreateGuestResponse {
        try await client.send("POST", "create_guest", body: request)
    }

    public func profile() async throws -> ProfileResponse {
        try await client.send("GET", "profile")
    }

    public func updateProfile(_ request: ProfileUpdateRequest) async throws {
        try await client.data("PATCH", "profile", body: request)
    }

    public func oauthLoginURL(_ provider: OAuthProvider, client oauthClient: OAuthClient) async throws -> OAuthLoginResponse {
        try await client.send("GET", "\(provider.rawValue)/login", query: [URLQueryItem(name: "client", value: oauthClient.rawValue)])
    }

    public func appleNativeLogin(_ request: AppleNativeLoginRequest) async throws -> LoginResponse {
        try await client.send("POST", "apple/native", body: request)
    }

    // MARK: games

    public func startGame(_ request: StartGameRequest) async throws -> StartGameResponse {
        try await client.send("POST", "start", body: request)
    }

    public func insertTurn(gameID: Int, _ turn: GameTurnRequest) async throws -> GameTurnResponse {
        try await client.send("POST", "\(gameID)/turns", body: turn)
    }

    public func updatePlayers(gameID: Int, players: [PlayerPayload]) async throws {
        try await client.data("PUT", "update/players", body: UpdatePlayersRequest(gameId: gameID, players: players))
    }

    public func endGame(_ request: GameEndRequest) async throws {
        try await client.data("PUT", "end", body: request)
    }

    public func replay(gameID: Int) async throws -> GameReplayPayload {
        try await client.send("GET", "\(gameID)/replay")
    }

    // MARK: stats

    public func statsView() async throws -> PlayerStatsView {
        try await client.send("GET", "stats_view")
    }

    public func statsViewCPU(boardSize: Int?, timer: Int?, cpuType: String?) async throws -> [PlayerStatsCPUView] {
        var query: [URLQueryItem] = []
        if let boardSize { query.append(URLQueryItem(name: "board_size", value: String(boardSize))) }
        if let timer { query.append(URLQueryItem(name: "timer", value: String(timer))) }
        if let cpuType, !cpuType.isEmpty { query.append(URLQueryItem(name: "cpu_type", value: cpuType)) }
        return try await client.send("GET", "stats_view_cpu", query: query)
    }

    public func statsViewHuman(boardSize: Int?, timer: Int?) async throws -> PlayerStatsView {
        var query: [URLQueryItem] = []
        if let boardSize { query.append(URLQueryItem(name: "board_size", value: String(boardSize))) }
        if let timer { query.append(URLQueryItem(name: "timer", value: String(timer))) }
        return try await client.send("GET", "stats_view_human", query: query)
    }

    public func profileStatsFilters(scope: String) async throws -> ProfileStatsFilters {
        try await client.send("GET", "profile_stats_filters", query: [URLQueryItem(name: "scope", value: scope)])
    }

    public func recentGames(limit: Int, offset: Int) async throws -> RecentGamesPage {
        try await client.send("GET", "recent_games", query: [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ])
    }

    // MARK: model

    public func cpuMove(_ request: CPUMoveRequest) async throws -> CPUMoveResponse {
        try await client.send("POST", "cpu_move", body: request)
    }
}
