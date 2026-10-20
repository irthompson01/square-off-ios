import Foundation

/// Shared URLSession plumbing for `LiveSquareOffAPI` and `LiveMatcherAPI`.
/// Auth is a bearer token (the server also accepts its cookie; the app never uses cookies).
struct RESTClient: Sendable {
    let baseURL: URL
    let session: URLSession
    let tokenProvider: (any TokenProvider)?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(baseURL: URL, session: URLSession, tokenProvider: (any TokenProvider)?) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
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
        if let token = tokenProvider?.accessToken() {
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
            throw APIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        return data
    }
}
