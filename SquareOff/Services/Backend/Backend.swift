import Foundation
import SquareOffCore
import SquareOffNet

/// Lets services that run off the main actor surface a one-line notice in the game on screen.
@MainActor
final class SessionNoticeRelay {
    weak var session: GameSession?

    nonisolated init() {}

    func post(_ text: String) {
        session?.notice = text
    }
}

/// One composed backend: REST client, matcher, socket factory, token store and identities for
/// the configured kind. Rebuilt wholesale when the kind changes; a running game keeps the
/// providers it was created with.
@MainActor
final class Backend {
    /// Debug hook (`-demoOnline`): faster bots for screenshots.
    nonisolated(unsafe) static var mockRoomConfiguration = MockRoomServer.Configuration()

    let configuration: BackendConfiguration
    let api: any SquareOffAPI
    let matcher: any MatcherAPI
    let tokenStore: any TokenStore
    let identity: IdentityStore
    let roomServer: MockRoomServer?
    private let urlSession: URLSession

    init(configuration: BackendConfiguration) {
        self.configuration = configuration
        urlSession = Self.makeURLSession()

        switch configuration.kind {
        case .mock:
            let tokens = UserDefaultsTokenStore(key: "mockAccessToken")
            tokenStore = tokens
            api = MockSquareOffAPI(tokenProvider: tokens)
            let server = MockRoomServer(configuration: Self.mockRoomConfiguration)
            roomServer = server
            matcher = MockMatcherAPI(server: server)
        case .live:
            let tokens = KeychainTokenStore(service: "com.novastrada.squareoff", account: "accessToken")
            tokenStore = tokens
            api = LiveSquareOffAPI(environment: configuration.environment, session: urlSession, tokenProvider: tokens)
            matcher = LiveMatcherAPI(environment: configuration.environment, session: urlSession, tokenProvider: tokens)
            roomServer = nil
        }
        identity = IdentityStore(backendID: configuration.id, api: api)
    }

    /// Injected collaborators (tests).
    init(configuration: BackendConfiguration, api: any SquareOffAPI, matcher: any MatcherAPI,
         tokenStore: any TokenStore, roomServer: MockRoomServer?, defaults: UserDefaults = .standard) {
        self.configuration = configuration
        self.api = api
        self.matcher = matcher
        self.tokenStore = tokenStore
        self.roomServer = roomServer
        urlSession = Self.makeURLSession()
        identity = IdentityStore(backendID: configuration.id, api: api, defaults: defaults)
    }

    /// No cookies (auth is the bearer header), short timeouts so a dead server fails fast.
    private static func makeURLSession() -> URLSession {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.httpCookieAcceptPolicy = .never
        sessionConfiguration.httpShouldSetCookies = false
        sessionConfiguration.timeoutIntervalForRequest = 15
        sessionConfiguration.waitsForConnectivity = false
        return URLSession(configuration: sessionConfiguration)
    }

    var isLive: Bool { configuration.kind == .live }

    func makeSocket() -> any GameSocket {
        if let roomServer { return MockGameSocket(server: roomServer) }
        return LiveGameSocket(url: configuration.environment.webSocketURL, session: urlSession)
    }

    /// Records Vs CPU and Pass & Play games (`/start`, `/turns`, `/end`) on both backends.
    func makeRecorder(account: Account, notices: SessionNoticeRelay) -> any GameRecorder {
        let identity = identity
        return ServerGameRecorder(
            api: api,
            humanPlayerID: account.serverPlayerID,
            ensureGuest: { try await identity.ensureGuest(name: "Guest", colorHex: Theme.playerColors[0]).playerID },
            localSeatIDs: identity.localSeatIDs,
            notices: notices
        )
    }

    /// On-device heuristics, except the CNN (server only) and, with the developer toggle on,
    /// every level for parity testing.
    func makeCPUProvider(config: GameConfig, notices: SessionNoticeRelay) -> any CPUMoveProvider {
        guard case .cpu(let level) = config.mode else { return LocalCPUMoveProvider() }
        if level == .cnn || configuration.cpuMovesFromServer {
            let levels: Set<CPULevel> = configuration.cpuMovesFromServer ? Set(CPULevel.allCases) : [.cnn]
            return ServerCPUMoveProvider(api: api, serverLevels: levels, notices: notices)
        }
        return LocalCPUMoveProvider()
    }

    /// Whether Level 3 can be picked for this setup (the Keras model is 8×8, two players).
    func supportsServerCPU(boardSize: Int, playerCount: Int) -> Bool {
        CPUAvailability.isCNNSelectable(kind: configuration.kind, boardSize: boardSize, playerCount: playerCount)
    }
}

nonisolated enum CPUAvailability {
    /// The CNN model on the server is hard-coded to an 8×8 board with two seats. The mock
    /// simulates it under the same rule so setup behaves identically on both backends.
    static func isCNNSelectable(kind: BackendKind, boardSize: Int, playerCount: Int) -> Bool {
        boardSize == 8 && playerCount == 2
    }

    static func footnote(kind: BackendKind, boardSize: Int) -> String {
        if boardSize != 8 { return "Level 3 (CNN) only plays on 8×8 boards." }
        switch kind {
        case .mock: return "Level 3 (CNN) is simulated by the in-app server. Switch to the local server in Profile › Developer for the real model."
        case .live: return "Level 3 (CNN) runs on the local server."
        }
    }
}
