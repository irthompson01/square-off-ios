import Foundation
import SquareOffCore
import SquareOffNet

/// Lets services that run off the main actor surface a one-line notice in the game on screen.
@MainActor
final class SessionNoticeRelay {
    weak var session: (any GamePresenting)?
    private var postedKeys: Set<String> = []

    nonisolated init() {}

    func post(_ text: String) {
        session?.notice = text
    }

    /// Posts once per key for the life of the relay (one game): repeated server fallbacks don't nag.
    func postOnce(key: String, _ text: String) {
        guard postedKeys.insert(key).inserted else { return }
        session?.notice = text
    }
}

/// Carries "the server ended this session" from the API clients (any thread) to the account
/// store on the main actor. One per `Backend`, so a replaced backend's late 401s go nowhere.
nonisolated final class SessionRelay: Sendable {
    nonisolated(unsafe) var onEnded: (@MainActor (SessionEndReason) -> Void)?

    init() {}

    func post(_ reason: SessionEndReason) {
        Task { @MainActor [self] in onEnded?(reason) }
    }
}

/// The API clients' `SessionRecovery`, bridged to the main-actor `IdentityStore`: a 401
/// `session_required` mints a new guest session and the request is retried once.
nonisolated final class SessionRecoveryRelay: Sendable {
    nonisolated(unsafe) var recover: (@MainActor () async -> Bool)?

    init() {}

    func run() async -> Bool {
        await recover?() ?? false
    }
}

/// One composed backend: REST client, matcher, socket factory, token stores and identities for
/// the configured kind. Rebuilt wholesale when the kind changes; a running game keeps the
/// providers it was created with.
@MainActor
final class Backend {
    #if DEBUG
    /// Debug hook (`-demoOnline`): faster bots for screenshots.
    nonisolated(unsafe) static var mockRoomConfiguration = MockRoomServer.Configuration()
    /// Debug hook (`-demoRole`): the seeded mock account's role (`superadmin` in the admin app).
    nonisolated(unsafe) static var mockDemoRole = "standard"
    #endif
    #if ADMIN_CONSOLE
    /// `/api/admin/*` over the same session and token (the admin console only).
    let adminAPI: any AdminAPI
    #endif

    let configuration: BackendConfiguration
    let api: any SquareOffAPI
    let matcher: any MatcherAPI
    /// The signed-in user's token.
    let tokenStore: any TokenStore
    /// The device's guest session token (sent whenever there is no user token).
    let guestTokens: any TokenStore
    /// What every client attaches: the user's token, else the guest's.
    let tokens: SessionTokenProvider
    let identity: IdentityStore
    let roomServer: MockRoomServer?
    let sessions = SessionRelay()
    let recovery = SessionRecoveryRelay()
    let urlSession: URLSession

    init(configuration: BackendConfiguration) {
        self.configuration = configuration
        urlSession = Self.makeURLSession()
        let sessions = sessions
        let recovery = recovery
        let onSessionEnded: @Sendable (SessionEndReason) -> Void = { sessions.post($0) }
        let sessionRecovery: SessionRecovery = { await recovery.run() }

        switch configuration.kind {
        case .mock:
            #if DEBUG
            let user = UserDefaultsTokenStore(key: "mockAccessToken")
            let guest = UserDefaultsTokenStore(key: "mockGuestToken")
            tokenStore = user
            guestTokens = guest
            tokens = SessionTokenProvider(user: user, guest: guest)
            let mock = MockSquareOffAPI(tokenProvider: tokens, onSessionEnded: onSessionEnded,
                                        sessionRecovery: sessionRecovery, demoRole: Self.mockDemoRole)
            api = mock
            let server = MockRoomServer(configuration: Self.mockRoomConfiguration)
            roomServer = server
            matcher = MockMatcherAPI(server: server)
            #if ADMIN_CONSOLE
            adminAPI = MockAdminAPI(accounts: mock)
            #endif
            #else
            fatalError("The mock backend is not part of release builds")
            #endif
        case .production, .local:
            let user = KeychainTokenStore(service: "com.novastrada.squareoff", account: "accessToken")
            let guest = KeychainTokenStore(service: "com.novastrada.squareoff", account: "guestToken.\(configuration.id)")
            tokenStore = user
            guestTokens = guest
            tokens = SessionTokenProvider(user: user, guest: guest)
            api = LiveSquareOffAPI(environment: configuration.environment, session: urlSession, tokenProvider: tokens,
                                   onSessionEnded: onSessionEnded, sessionRecovery: sessionRecovery)
            matcher = LiveMatcherAPI(environment: configuration.environment, session: urlSession, tokenProvider: tokens,
                                     sessionRecovery: sessionRecovery)
            roomServer = nil
            #if ADMIN_CONSOLE
            adminAPI = LiveAdminAPI(environment: configuration.environment, session: urlSession, tokenProvider: tokens,
                                    onSessionEnded: onSessionEnded)
            #endif
        }
        identity = IdentityStore(backendID: configuration.id, api: api, userTokens: tokenStore, guestTokens: guestTokens)
        let identity = identity
        recovery.recover = { await identity.recoverSession() }
    }

    /// Injected collaborators (tests).
    init(configuration: BackendConfiguration, api: any SquareOffAPI, matcher: any MatcherAPI,
         tokenStore: any TokenStore, guestTokens: any TokenStore = InMemoryTokenStore(),
         roomServer: MockRoomServer?, defaults: UserDefaults = .standard) {
        self.configuration = configuration
        self.api = api
        self.matcher = matcher
        self.tokenStore = tokenStore
        self.guestTokens = guestTokens
        tokens = SessionTokenProvider(user: tokenStore, guest: guestTokens)
        self.roomServer = roomServer
        urlSession = Self.makeURLSession()
        identity = IdentityStore(backendID: configuration.id, api: api, userTokens: tokenStore, guestTokens: guestTokens,
                                 defaults: defaults)
        let identity = identity
        recovery.recover = { await identity.recoverSession() }
        #if ADMIN_CONSOLE
        adminAPI = MockAdminAPI(accounts: nil, latency: .zero)
        #endif
    }

    /// No cookies at all (auth is the bearer header, and the server reads its cookie *before*
    /// the header, so a stored one would override whichever token we meant to send); short
    /// timeouts so a dead server fails fast. Shared by the REST clients and the socket.
    private static func makeURLSession() -> URLSession {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.httpCookieAcceptPolicy = .never
        sessionConfiguration.httpShouldSetCookies = false
        sessionConfiguration.httpCookieStorage = nil
        sessionConfiguration.timeoutIntervalForRequest = 15
        sessionConfiguration.waitsForConnectivity = false
        return URLSession(configuration: sessionConfiguration)
    }

    /// A real server (production or the docker stack), as opposed to the in-app mock.
    var isLive: Bool { configuration.kind != .mock }
    var isProduction: Bool { configuration.kind == .production }

    /// The handshake carries the session token (read when connecting, so a renewed guest token
    /// or a fresh sign-in is picked up on reconnect); the mock socket gets the id it stands for.
    func makeSocket() -> any GameSocket {
        if let roomServer {
            return MockGameSocket(server: roomServer, playerID: MockSquareOffAPI.playerID(forToken: tokens.accessToken()))
        }
        return LiveGameSocket(url: configuration.environment.webSocketURL, session: urlSession, tokenProvider: tokens)
    }

    /// A fresh socket plus the REST pieces the lobby and an online game use. A refused handshake
    /// (`session_required`, a dead guest token) mints a new guest session and connects again.
    func makeOnlineTransport() -> OnlineTransport {
        let identity = identity
        let connection = OnlineConnection(socket: makeSocket(), recovery: { await identity.recoverSession() })
        return OnlineTransport(connection: connection, matcher: matcher, api: api,
                               inviteBase: configuration.inviteOrigin, backendID: configuration.id)
    }

    /// Records Vs CPU and Pass & Play games (`/start`, `/turns`, `/end`) on both backends.
    func makeRecorder(account: Account, notices: SessionNoticeRelay) -> any GameRecorder {
        let identity = identity
        return ServerGameRecorder(
            api: api,
            humanPlayerID: account.profile?.id,
            ensureGuest: { try await identity.ensureGuest().playerID },
            notices: notices
        )
    }

    /// On-device heuristics, except the engine tiers (levels 7–8, server only) and, with the
    /// developer toggle on, every level for parity testing.
    func makeCPUProvider(config: GameConfig, notices: SessionNoticeRelay) -> any CPUMoveProvider {
        guard case .cpu(let level) = config.mode else { return LocalCPUMoveProvider() }
        if level.isServerOnly || configuration.cpuMovesFromServer {
            let levels = configuration.cpuMovesFromServer ? Set(CPULevel.allCases) : Set(CPULevel.allCases.filter(\.isServerOnly))
            return ServerCPUMoveProvider(api: api, serverLevels: levels, notices: notices)
        }
        return LocalCPUMoveProvider()
    }
}

nonisolated enum CPUAvailability {
    /// The engine tiers play 6×6 to 12×12 (`src/ai/state.py`); every other level plays any board.
    static func isSelectable(_ level: CPULevel, boardSize: Int) -> Bool {
        level.supportedBoardSizes.contains(boardSize)
    }

    /// The levels the picker greys out for a board size.
    static func unavailableLevels(boardSize: Int) -> Set<CPULevel> {
        Set(CPULevel.selectable.filter { !isSelectable($0, boardSize: boardSize) })
    }

    static func footnote(kind: BackendKind, level: CPULevel) -> String {
        guard level.isServerOnly else { return "Levels 1–6 play on this device." }
        switch kind {
        case .mock: return "Levels 7–8 are simulated by the in-app server (6×6 to 12×12). Switch to a real server in Profile › Developer for the real engine."
        case .local: return "Levels 7–8 run on the local server (6×6 to 12×12). If it can't be reached they play Level 6 on this device."
        case .production: return "Levels 7–8 run on the Square Off server (6×6 to 12×12). If it can't be reached they play Level 6 on this device."
        }
    }
}
