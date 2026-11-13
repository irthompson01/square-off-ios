import Foundation

/// Shared URLSession plumbing for `LiveSquareOffAPI`, `LiveMatcherAPI` and `LiveAdminAPI`.
/// Auth is a bearer token: the signed-in user's, else the device's guest session. The server
/// also accepts its cookie (and reads it first), which is why the app never stores cookies.
struct RESTClient: Sendable {
    let baseURL: URL
    let session: URLSession
    let tokenProvider: (any TokenProvider)?
    /// Called before a 401 with one of the server's session codes is thrown, and only when a
    /// **user** token was attached: the account store signs the user out and says why.
    let onSessionEnded: (@Sendable (SessionEndReason) -> Void)?
    /// Mints or renews the guest session after a 401 `session_required` (or a guest token the
    /// server no longer knows); `true` means the request is retried once with the new token.
    let sessionRecovery: SessionRecovery?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(baseURL: URL, session: URLSession, tokenProvider: (any TokenProvider)?,
         onSessionEnded: (@Sendable (SessionEndReason) -> Void)? = nil,
         sessionRecovery: SessionRecovery? = nil) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
        self.onSessionEnded = onSessionEnded
        self.sessionRecovery = sessionRecovery
    }

    func send<Response: Decodable>(_ method: String, _ path: String, query: [URLQueryItem] = [],
                                   retry: Bool = true) async throws -> Response {
        try decoder.decode(Response.self, from: try await data(method, path, query: query, retry: retry))
    }

    func send<Response: Decodable>(
        _ method: String, _ path: String, query: [URLQueryItem] = [], body: some Encodable, retry: Bool = true
    ) async throws -> Response {
        try decoder.decode(Response.self, from: try await data(method, path, query: query, body: body, retry: retry))
    }

    @discardableResult
    func data(_ method: String, _ path: String, query: [URLQueryItem] = [], retry: Bool = true) async throws -> Data {
        try await perform(method, path, query: query, body: nil, retry: retry)
    }

    @discardableResult
    func data(_ method: String, _ path: String, query: [URLQueryItem] = [], body: some Encodable,
              retry: Bool = true) async throws -> Data {
        try await perform(method, path, query: query, body: try encoder.encode(body), retry: retry)
    }

    private func perform(_ method: String, _ path: String, query: [URLQueryItem], body: Data?, retry: Bool) async throws -> Data {
        var url = baseURL.appending(path: path)
        if !query.isEmpty {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.queryItems = query
            url = components.url!
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        let token = tokenProvider?.accessToken()
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw APIError.timeout
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let error = APIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
            if http.statusCode == 401 {
                let kind = token.map { tokenProvider?.kind(of: $0) ?? .user }
                // No session, or a guest session the server dropped: mint a new guest and go again.
                // A user token that stopped working is a sign-out, never silently replaced.
                let recoverable = error.isSessionRequired || (kind == .guest && error.sessionEndReason != nil)
                if retry, recoverable, let sessionRecovery, await sessionRecovery() {
                    return try await perform(method, path, query: query, body: body, retry: false)
                }
                if kind == .user, let reason = error.sessionEndReason { onSessionEnded?(reason) }
            }
            throw error
        }
        return data
    }
}
