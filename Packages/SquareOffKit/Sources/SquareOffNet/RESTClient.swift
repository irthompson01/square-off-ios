import Foundation

/// Shared URLSession plumbing for `LiveSquareOffAPI` and `LiveMatcherAPI`.
/// Auth is a bearer token (the server also accepts its cookie; the app never uses cookies).
struct RESTClient: Sendable {
    let baseURL: URL
    let session: URLSession
    let tokenProvider: (any TokenProvider)?
    /// Called before a 401 with one of the server's session codes is thrown, and only when a
    /// token was attached: the account store signs the user out and says why.
    let onSessionEnded: (@Sendable (SessionEndReason) -> Void)?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(baseURL: URL, session: URLSession, tokenProvider: (any TokenProvider)?,
         onSessionEnded: (@Sendable (SessionEndReason) -> Void)? = nil) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
        self.onSessionEnded = onSessionEnded
    }

    func send<Response: Decodable>(_ method: String, _ path: String, query: [URLQueryItem] = []) async throws -> Response {
        try decoder.decode(Response.self, from: try await data(method, path, query: query))
    }

    func send<Response: Decodable>(
        _ method: String, _ path: String, query: [URLQueryItem] = [], body: some Encodable
    ) async throws -> Response {
        try decoder.decode(Response.self, from: try await data(method, path, query: query, body: body))
    }

    @discardableResult
    func data(_ method: String, _ path: String, query: [URLQueryItem] = []) async throws -> Data {
        try await perform(method, path, query: query, body: nil)
    }

    @discardableResult
    func data(_ method: String, _ path: String, query: [URLQueryItem] = [], body: some Encodable) async throws -> Data {
        try await perform(method, path, query: query, body: try encoder.encode(body))
    }

    private func perform(_ method: String, _ path: String, query: [URLQueryItem], body: Data?) async throws -> Data {
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
            if token != nil, let reason = error.sessionEndReason { onSessionEnded?(reason) }
            throw error
        }
        return data
    }
}
