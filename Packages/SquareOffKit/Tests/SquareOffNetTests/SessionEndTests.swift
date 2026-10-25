import Foundation
import Testing
@testable import SquareOffNet

/// Answers every request with a canned status and body; records the requests it saw.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = "{}"
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private struct StaticToken: TokenProvider {
    let token: String?
    func accessToken() -> String? { token }
}

private final class ReasonBox: @unchecked Sendable {
    var reasons: [SessionEndReason] = []
}

@Suite("Session end detection", .serialized)
struct SessionEndTests {
    private func client(token: String?, box: ReasonBox) -> LiveSquareOffAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return LiveSquareOffAPI(environment: .local, session: URLSession(configuration: configuration),
                                tokenProvider: StaticToken(token: token), onSessionEnded: { box.reasons.append($0) })
    }

    @Test func codesMapToReasons() {
        for reason in SessionEndReason.allCases {
            #expect(APIError.http(status: 401, body: #"{"detail":"\#(reason.rawValue)"}"#).sessionEndReason == reason)
        }
        #expect(APIError.http(status: 401, body: #"{"detail":"Invalid credentials"}"#).sessionEndReason == nil)
        #expect(APIError.http(status: 403, body: #"{"detail":"account_disabled"}"#).sessionEndReason == nil)
        #expect(APIError.timeout.sessionEndReason == nil)
    }

    @Test func hookFiresForARevokedTokenButNotForABadPassword() async throws {
        let box = ReasonBox()
        StubURLProtocol.status = 401
        StubURLProtocol.body = #"{"detail":"session_revoked"}"#
        StubURLProtocol.requests = []
        let api = client(token: "stale", box: box)
        #expect(try await api.checkAuth() == false)
        #expect(box.reasons == [.revoked])
        #expect(StubURLProtocol.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer stale")

        StubURLProtocol.body = #"{"detail":"Invalid credentials"}"#
        await #expect(throws: APIError.self) {
            _ = try await api.login(LoginRequest(emailOrUsername: "ian", password: "nope"))
        }
        #expect(box.reasons == [.revoked])
        #expect(StubURLProtocol.requests.last?.url?.query() == "client=ios")
    }

    @Test func hookIsSilentWithoutAToken() async throws {
        let box = ReasonBox()
        StubURLProtocol.status = 401
        StubURLProtocol.body = #"{"detail":"Token has expired"}"#
        let api = client(token: nil, box: box)
        #expect(try await api.checkAuth() == false)
        #expect(box.reasons.isEmpty)
    }
}
