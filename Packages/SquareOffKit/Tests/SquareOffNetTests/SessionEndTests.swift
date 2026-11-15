import Foundation
import Testing
@testable import SquareOffNet

/// Answers requests from a queue of canned responses (then a default); records what it saw.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = "{}"
    /// Consumed first-in first-out before falling back to `status` / `body`.
    nonisolated(unsafe) static var queue: [(status: Int, body: String)] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []

    static func reset(status: Int = 200, body: String = "{}", queue: [(status: Int, body: String)] = []) {
        self.status = status
        self.body = body
        self.queue = queue
        requests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        let (status, body) = Self.queue.isEmpty ? (Self.status, Self.body) : Self.queue.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// A token the test can swap mid-flight (what the app's Keychain store does after recovery).
private final class TokenBox: TokenProvider, @unchecked Sendable {
    var token: String?
    var kind: TokenKind

    init(token: String?, kind: TokenKind = .user) {
        self.token = token
        self.kind = kind
    }

    func accessToken() -> String? { token }
    func kind(of token: String) -> TokenKind { kind }
}

private final class Recorder: @unchecked Sendable {
    var reasons: [SessionEndReason] = []
    var recoveries = 0
}

private let cpuBody = ##"{"id":6,"cpu_type":"random","display_name":"CPU (Random)","color":"#49F268"}"##
private let sessionRequired = #"{"detail":"session_required"}"#

@Suite("Session end detection and guest recovery", .serialized)
struct SessionEndTests {
    private func client(_ box: TokenBox, recorder: Recorder, recover: (@Sendable () -> Bool)? = nil) -> LiveSquareOffAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return LiveSquareOffAPI(environment: .local, session: URLSession(configuration: configuration),
                                tokenProvider: box, onSessionEnded: { recorder.reasons.append($0) },
                                sessionRecovery: recover.map { recover in { @Sendable in recorder.recoveries += 1; return recover() } })
    }

    @Test func codesMapToReasons() {
        for reason in SessionEndReason.allCases {
            #expect(APIError.http(status: 401, body: #"{"detail":"\#(reason.rawValue)"}"#).sessionEndReason == reason)
        }
        #expect(APIError.http(status: 401, body: #"{"detail":"Invalid credentials"}"#).sessionEndReason == nil)
        #expect(APIError.http(status: 403, body: #"{"detail":"account_disabled"}"#).sessionEndReason == nil)
        #expect(APIError.timeout.sessionEndReason == nil)
        #expect(APIError.http(status: 401, body: sessionRequired).isSessionRequired)
        #expect(APIError.http(status: 401, body: sessionRequired).sessionEndReason == nil)
        #expect(APIError.http(status: 401, body: #"{"detail":"account_required"}"#).isAccountRequired)
        #expect(!APIError.http(status: 403, body: sessionRequired).isSessionRequired)
    }

    @Test func hookFiresForARevokedUserTokenButNotForABadPassword() async throws {
        let recorder = Recorder()
        StubURLProtocol.reset(status: 401, body: #"{"detail":"session_revoked"}"#)
        let api = client(TokenBox(token: "stale"), recorder: recorder, recover: { true })
        #expect(try await api.checkAuth() == false)
        #expect(recorder.reasons == [.revoked])
        #expect(recorder.recoveries == 0, "a user token is never silently replaced")
        #expect(StubURLProtocol.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer stale")

        StubURLProtocol.body = #"{"detail":"Invalid credentials"}"#
        await #expect(throws: APIError.self) {
            _ = try await api.login(LoginRequest(emailOrUsername: "ian", password: "nope"))
        }
        #expect(recorder.reasons == [.revoked])
        #expect(StubURLProtocol.requests.last?.url?.query() == "client=ios")
    }

    @Test func hookIsSilentWithoutAToken() async throws {
        let recorder = Recorder()
        StubURLProtocol.reset(status: 401, body: #"{"detail":"Token has expired"}"#)
        let api = client(TokenBox(token: nil), recorder: recorder)
        #expect(try await api.checkAuth() == false)
        #expect(recorder.reasons.isEmpty)
    }

    @Test func sessionRequiredMintsAGuestAndRetriesOnce() async throws {
        let recorder = Recorder()
        let box = TokenBox(token: nil, kind: .guest)
        StubURLProtocol.reset(queue: [(401, sessionRequired), (200, cpuBody)])
        let api = client(box, recorder: recorder, recover: { box.token = "fresh-guest"; return true })
        let cpu = try await api.cpuPlayer(.random)
        #expect(cpu.cpuType == "random")
        #expect(recorder.recoveries == 1)
        #expect(recorder.reasons.isEmpty)
        #expect(StubURLProtocol.requests.count == 2)
        #expect(StubURLProtocol.requests[0].value(forHTTPHeaderField: "Authorization") == nil)
        #expect(StubURLProtocol.requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer fresh-guest")
    }

    @Test func aDeadGuestTokenIsReplacedNotSignedOut() async throws {
        let recorder = Recorder()
        let box = TokenBox(token: "old-guest", kind: .guest)
        StubURLProtocol.reset(queue: [(401, #"{"detail":"session_revoked"}"#), (200, cpuBody)])
        let api = client(box, recorder: recorder, recover: { box.token = "new-guest"; return true })
        _ = try await api.cpuPlayer(.random)
        #expect(recorder.recoveries == 1)
        #expect(recorder.reasons.isEmpty)
        #expect(StubURLProtocol.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer new-guest")
    }

    @Test func failedRecoveryThrowsTheOriginalError() async throws {
        let recorder = Recorder()
        StubURLProtocol.reset(status: 401, body: sessionRequired)
        let api = client(TokenBox(token: nil), recorder: recorder, recover: { false })
        await #expect(throws: APIError.self) { _ = try await api.cpuPlayer(.random) }
        #expect(recorder.recoveries == 1)
        #expect(StubURLProtocol.requests.count == 1)
    }

    @Test func accountRequiredIsNotRecovered() async throws {
        let recorder = Recorder()
        StubURLProtocol.reset(status: 401, body: #"{"detail":"account_required"}"#)
        let api = client(TokenBox(token: "guest-token", kind: .guest), recorder: recorder, recover: { true })
        #expect(try await api.checkAuth() == false)
        #expect(recorder.recoveries == 0)
        #expect(recorder.reasons.isEmpty)
    }

    @Test func createGuestNeverRecoversThroughItself() async throws {
        let recorder = Recorder()
        StubURLProtocol.reset(status: 401, body: sessionRequired)
        let api = client(TokenBox(token: nil), recorder: recorder, recover: { true })
        await #expect(throws: APIError.self) {
            _ = try await api.createGuest(CreateGuestRequest(name: "Guest", color: "#0583D2"))
        }
        #expect(recorder.recoveries == 0)
        #expect(StubURLProtocol.requests.count == 1)
    }

    @Test func retryHappensAtMostOnce() async throws {
        let recorder = Recorder()
        let box = TokenBox(token: nil, kind: .guest)
        StubURLProtocol.reset(status: 401, body: sessionRequired)
        let api = client(box, recorder: recorder, recover: { box.token = "g"; return true })
        await #expect(throws: APIError.self) { _ = try await api.cpuPlayer(.random) }
        #expect(recorder.recoveries == 1)
        #expect(StubURLProtocol.requests.count == 2)
    }
}
