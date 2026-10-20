import Foundation
import SquareOffCore
import SquareOffNet
@testable import SquareOff

/// A `SquareOffAPI` that records every call, can fail or delay chosen methods, and answers
/// with canned data. Test-only.
actor SpyAPI: SquareOffAPI {
    private(set) var calls: [String] = []
    private(set) var startRequests: [StartGameRequest] = []
    private(set) var turnRequests: [GameTurnRequest] = []
    private(set) var endRequests: [GameEndRequest] = []
    var failing: Set<String> = []
    var delays: [String: Duration] = [:]
    var authenticated = false
    var profileResponse = ProfileResponse(id: "user-1", username: "ian", email: "ian@example.com", firstName: "Ian", lastName: "T", color: "#0583D2", createdAt: "2026-10-19T00:00:00")
    var cpuMoveReply = CPUMoveResponse(row: 0, col: 0)
    var oauthURL = URL(string: "squareoff://auth?token=spy-token")!

    func setFailing(_ names: Set<String>) { failing = names }
    func setDelay(_ name: String, _ duration: Duration) { delays[name] = duration }
    func setAuthenticated(_ value: Bool) { authenticated = value }
    func setCPUMoveReply(_ reply: CPUMoveResponse) { cpuMoveReply = reply }
    func setOAuthURL(_ url: URL) { oauthURL = url }

    private func hit(_ name: String) async throws {
        calls.append(name)
        if let delay = delays[name] { try await Task.sleep(for: delay) }
        if failing.contains(name) { throw APIError.http(status: 500, body: #"{"detail":"spy failure"}"#) }
    }

    func guests() async throws -> GuestsResponse { try await hit("guests"); return GuestsResponse(guests: ["g1"]) }
    func cpuPlayer(_ level: CPULevel) async throws -> CPUPlayerResponse {
        try await hit("cpuPlayer")
        return CPUPlayerResponse(id: 100 + level.number, cpuType: level.cpuType, displayName: "CPU", color: "#FF3131")
    }
    func login(_ request: LoginRequest) async throws -> LoginResponse {
        try await hit("login")
        guard request.password == "secret" else { throw APIError.http(status: 401, body: #"{"detail":"Invalid credentials"}"#) }
        return LoginResponse(message: "ok", accessToken: "spy-token")
    }
    func register(_ request: RegisterRequest) async throws -> RegisterResponse { try await hit("register"); return RegisterResponse(message: "ok", playerId: "user-1") }
    func logout() async throws { try await hit("logout") }
    func checkAuth() async throws -> Bool { try await hit("checkAuth"); return authenticated }
    func createGuest(_ request: CreateGuestRequest) async throws -> CreateGuestResponse { try await hit("createGuest"); return CreateGuestResponse(message: "ok", playerId: "guest-uuid") }
    func profile() async throws -> ProfileResponse { try await hit("profile"); return profileResponse }
    func updateProfile(_ request: ProfileUpdateRequest) async throws { try await hit("updateProfile") }
    func oauthLoginURL(_ provider: OAuthProvider, client: OAuthClient) async throws -> OAuthLoginResponse { try await hit("oauthLoginURL"); return OAuthLoginResponse(url: oauthURL, state: "s") }
    func appleNativeLogin(_ request: AppleNativeLoginRequest) async throws -> LoginResponse { try await hit("appleNativeLogin"); return LoginResponse(message: "ok", accessToken: "apple-token") }
    func startGame(_ request: StartGameRequest) async throws -> StartGameResponse {
        try await hit("startGame")
        startRequests.append(request)
        return StartGameResponse(gameId: 42, participants: request.players.enumerated().map {
            StartGameResponse.Participant(playerId: $1.playerId ?? "\($1.id)", participantId: 500 + $0)
        })
    }
    func insertTurn(gameID: Int, _ turn: GameTurnRequest) async throws -> GameTurnResponse {
        try await hit("insertTurn")
        turnRequests.append(turn)
        return GameTurnResponse(turnId: turnRequests.count)
    }
    func updatePlayers(gameID: Int, players: [PlayerPayload]) async throws { try await hit("updatePlayers") }
    func endGame(_ request: GameEndRequest) async throws { try await hit("endGame"); endRequests.append(request) }
    func replay(gameID: Int) async throws -> GameReplayPayload { try await hit("replay"); return GameReplayPayload(gameId: gameID, boardSize: 6, timer: 0, gameType: "local", participants: [], turns: []) }
    func statsView() async throws -> PlayerStatsView {
        try await hit("statsView")
        return PlayerStatsView(playerId: "user-1", username: "ian", email: "", firstName: "", lastName: "", color: "#0583D2", createdAt: "", totalGamesPlayed: 1, gamesWon: 1, gamesLost: 0, winPercentage: 100, avgGameDuration: 3, highestScore: 20, avgFinalScore: 20, localGamesPlayed: 1)
    }
    func statsViewCPU(boardSize: Int?, timer: Int?, cpuType: String?) async throws -> [PlayerStatsCPUView] { try await hit("statsViewCPU"); return [] }
    func recentGames(limit: Int, offset: Int) async throws -> RecentGamesPage { try await hit("recentGames"); return RecentGamesPage(games: [], total: 0) }
    func cpuMove(_ request: CPUMoveRequest) async throws -> CPUMoveResponse { try await hit("cpuMove"); return cpuMoveReply }
}

/// A matcher nothing calls in these tests.
struct UnusedMatcher: MatcherAPI {
    func openRooms(boardSize: Int?, timer: Int?, limit: Int, offset: Int) async throws -> [OpenRoomDTO] { [] }
    func advertise(_ request: AdvertiseRoomRequest) async throws -> AdvertiseRoomResponse { AdvertiseRoomResponse(roomCode: request.roomCode, listed: true, slotsFilled: 1) }
    func delist(roomCode: Int) async throws {}
    func quickMatch(_ request: QuickMatchRequest) async throws -> QuickMatchResult { QuickMatchResult(status: .pending, action: .queued, ticketId: "t") }
    func quickMatchStatus(ticketID: String, requesterID: String) async throws -> QuickMatchResult { QuickMatchResult(status: .pending, action: .queued, ticketId: ticketID) }
    func cancelQuickMatch(ticketID: String, requesterID: String) async throws {}
}

extension Backend {
    /// A backend over a spy API with an in-memory token store (and its own UserDefaults suite).
    @MainActor
    static func test(api: any SquareOffAPI, kind: BackendKind = .live, token: String? = nil, cpuMovesFromServer: Bool = false) -> Backend {
        var configuration = kind == .live ? BackendConfiguration.localDocker : .mock
        configuration.cpuMovesFromServer = cpuMovesFromServer
        let defaults = UserDefaults(suiteName: "SquareOffTests.\(UUID().uuidString)")!
        return Backend(configuration: configuration, api: api, matcher: UnusedMatcher(),
                       tokenStore: InMemoryTokenStore(token: token), roomServer: nil, defaults: defaults)
    }
}

/// A JWT-shaped string whose payload carries `exp`; the signature is garbage (never verified here).
func fakeJWT(expiringAt date: Date) -> String {
    let payload = try! JSONSerialization.data(withJSONObject: ["sub": "x", "exp": Int(date.timeIntervalSince1970)])
    let b64 = { (d: Data) in d.base64EncodedString().replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_") }
    return "\(b64(Data(#"{"alg":"HS256"}"#.utf8))).\(b64(payload)).sig"
}
