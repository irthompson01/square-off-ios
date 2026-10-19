import Foundation
import SquareOffCore

/// URLSession client. Auth is the same httpOnly `square_off_access_token` cookie the web uses:
/// `HTTPCookieStorage` keeps it and sends it on every request (the web's `credentials: "include"`).
public struct LiveSquareOffAPI: SquareOffAPI {
    private let environment: APIEnvironment
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(environment: APIEnvironment, session: URLSession = .shared) {
        self.environment = environment
        self.session = session
    }

    public func guests() async throws -> GuestsResponse {
        try await send("GET", "guests")
    }

    public func cpuPlayer(_ level: CPULevel) async throws -> CPUPlayerResponse {
        try await send("GET", "cpu_player/\(level.cpuType)")
    }

    public func login(_ request: LoginRequest) async throws {
        _ = try await data("POST", "login", body: request)
    }

    public func register(_ request: RegisterRequest) async throws {
        _ = try await data("POST", "register", body: request)
    }

    public func logout() async throws {
        _ = try await data("POST", "logout", body: Optional<String>.none)
    }

    public func checkAuth() async throws -> Bool {
        do {
            _ = try await data("GET", "check-auth", body: Optional<String>.none)
            return true
        } catch APIError.http(status: 401, _) {
            return false
        }
    }

    public func startGame(_ request: StartGameRequest) async throws -> StartGameResponse {
        try await send("POST", "start", body: request)
    }

    public func insertTurn(gameID: Int, _ turn: GameTurnRequest) async throws -> GameTurnResponse {
        try await send("POST", "\(gameID)/turns", body: turn)
    }

    public func cpuMove(_ request: CPUMoveRequest) async throws -> CPUMoveResponse {
        try await send("POST", "cpu_move", body: request)
    }

    // MARK: Plumbing

    private func send<Response: Decodable>(_ method: String, _ path: String) async throws -> Response {
        try await send(method, path, body: Optional<String>.none)
    }

    private func send<Body: Encodable, Response: Decodable>(
        _ method: String, _ path: String, body: Body?
    ) async throws -> Response {
        try decoder.decode(Response.self, from: try await data(method, path, body: body))
    }

    private func data<Body: Encodable>(_ method: String, _ path: String, body: Body?) async throws -> Data {
        var request = URLRequest(url: environment.baseURL.appending(path: path))
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        return data
    }
}
