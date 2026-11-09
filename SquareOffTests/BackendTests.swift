import Foundation
import SquareOffCore
import SquareOffNet
import Testing
@testable import SquareOff

@MainActor
struct ServerGameRecorderTests {
    private func passAndPlay(size: Int = 4, players: Int = 2) -> GameConfig {
        GameConfig(mode: .passAndPlay, boardSize: size, timerSeconds: 0, players: (1...players).map {
            SetupPlayer(id: $0, name: "P\($0)", colorHex: Theme.playerColors[$0 - 1])
        })
    }

    private func session(_ config: GameConfig, api: SpyAPI, account: Account = .guest(nil), cpu: any CPUMoveProvider = LocalCPUMoveProvider()) -> (GameSession, Backend) {
        let backend = Backend.test(api: api)
        let notices = SessionNoticeRelay()
        let session = GameSession(config: config, cpu: cpu, recorder: backend.makeRecorder(account: account, notices: notices), thinkDelay: 0...0)
        notices.session = session
        return (session, backend)
    }

    private func settle() async throws { try await Task.sleep(for: .milliseconds(250)) }

    @Test func recordsStartTurnsAndEndInOrderWithServerIDs() async throws {
        let api = SpyAPI()
        let (session, backend) = session(passAndPlay(size: 4), api: api)
        await session.start()
        for row in 0..<4 { for col in 0..<4 { session.tap(Cell(row: row, col: col)) } }
        try await settle()

        let calls = await api.calls
        #expect(calls.first == "createGuest")   // the device guest identity was minted on first use
        #expect(calls.dropFirst().prefix(1) == ["startGame"])
        #expect(calls.filter { $0 == "insertTurn" }.count == 16)
        #expect(calls.last == "endGame")
        #expect(backend.identity.guest?.playerID == "guest-uuid")

        let start = try #require(await api.startRequests.first)
        #expect(start.players.map(\.playerId) == ["guest-uuid", nil], "only the caller's seat carries an id; the server mints the rest")
        #expect(backend.guestTokens.accessToken() == "spy-guest-token-1")
        let turns = await api.turnRequests
        #expect(turns.map(\.participantId) == Array(repeating: [500, 501], count: 8).flatMap { $0 })
        #expect(turns[0].playerId == "guest-uuid")
        #expect(turns[1].playerId == "minted-1", "seat 2 records under the guest the server minted for it")
        let end = try #require(await api.endRequests.first)
        #expect(end.scores.map(\.playerId) == ["guest-uuid", "minted-1"])
        #expect(end.winnerId == (session.game.isDraw ? "" : (session.game.standings[0].id == 1 ? "guest-uuid" : "minted-1")))
    }

    @Test func cpuSeatUsesTheServerCPUIdAndASignedInUserTheirUUID() async throws {
        let api = SpyAPI()
        let config = GameConfig(mode: .cpu(.maxMin), boardSize: 4, timerSeconds: 0, players: [SetupPlayer(id: 1, name: "Me", colorHex: Theme.playerColors[0])])
        let profile = ProfileResponse(id: "user-uuid", username: "ian", email: "", firstName: "", lastName: "", color: "#0583D2", createdAt: "")
        let (session, _) = session(config, api: api, account: .signedIn(profile), cpu: ScriptedCPU([]))
        await session.start()
        try await settle()
        let start = try #require(await api.startRequests.first)
        #expect(start.players.map(\.playerId) == ["user-uuid", "103"])   // SpyAPI: 100 + level number (max-min is level 3)
        #expect(start.cpuType == "max-min")
        #expect(await api.calls.contains("cpuPlayer"))
        #expect(!(await api.calls.contains("createGuest")))
        session.stop()
    }

    @Test func slowStartNeverBlocksTapping() async throws {
        let api = SpyAPI()
        await api.setDelay("startGame", .milliseconds(500))
        let (session, _) = session(passAndPlay(), api: api)
        await session.start()
        session.tap(Cell(row: 0, col: 0))
        #expect(session.game.moves.count == 1)
        try await Task.sleep(for: .milliseconds(700))
        #expect(await api.calls == ["createGuest", "startGame", "insertTurn"])   // still in order
    }

    @Test func aFailureDisablesRecordingAndNoticesOnce() async throws {
        let api = SpyAPI()
        await api.setFailing(["insertTurn"])
        let (session, _) = session(passAndPlay(), api: api)
        await session.start()
        session.tap(Cell(row: 0, col: 0))
        session.tap(Cell(row: 1, col: 1))
        try await settle()
        #expect(await api.calls.filter { $0 == "insertTurn" }.count == 1)
        #expect(session.notice == ServerGameRecorder.offlineNotice)
        #expect(session.game.moves.count == 2)
    }

    @Test func rematchStartsANewRecordedGame() async throws {
        let api = SpyAPI()
        let (session, _) = session(passAndPlay(size: 2), api: api)
        await session.start()
        for cell in [Cell(row: 0, col: 0), Cell(row: 1, col: 1), Cell(row: 0, col: 1), Cell(row: 1, col: 0)] { session.tap(cell) }
        try await settle()
        session.restart()
        try await settle()
        #expect(await api.calls.filter { $0 == "startGame" }.count == 2)
        #expect(await api.calls.filter { $0 == "endGame" }.count == 1)
        session.stop()
    }
}

@MainActor
struct ServerCPUMoveProviderTests {
    private func game() -> Game {
        var game = Game(boardSize: 8, players: [
            PlayerState(id: 1, name: "Me", colorHex: "#0583D2"),
            PlayerState(id: 2, name: "CPU", colorHex: "#FF3131", isCPU: true, cpuLevel: .cnn),
        ])
        try! game.place(at: Cell(row: 0, col: 0))
        return game
    }

    @Test func serverReplyIsUsedWhenLegal() async throws {
        let api = SpyAPI()
        await api.setCPUMoveReply(CPUMoveResponse(row: 4, col: 4))
        let provider = ServerCPUMoveProvider(api: api, serverLevels: [.cnn], notices: SessionNoticeRelay())
        #expect(await provider.move(for: game(), level: .cnn) == Cell(row: 4, col: 4))
        #expect(await api.calls == ["cpuMove"])
    }

    @Test func onlyServerLevelsHitTheAPI() async throws {
        let api = SpyAPI()
        let provider = ServerCPUMoveProvider(api: api, serverLevels: [.cnn], notices: SessionNoticeRelay())
        let cell = await provider.move(for: game(), level: .maxMin)
        #expect(game().board[cell] == nil)
        #expect(await api.calls.isEmpty)
    }

    @Test func failuresOccupiedAndTimeoutsFallBackWithANotice() async throws {
        let api = SpyAPI()
        let notices = SessionNoticeRelay()
        let session = GameSession(config: GameConfig(mode: .cpu(.cnn), boardSize: 8, timerSeconds: 0, players: [SetupPlayer(id: 1, name: "Me", colorHex: "#0583D2")]))
        notices.session = session
        let provider = ServerCPUMoveProvider(api: api, serverLevels: [.cnn], notices: notices, timeout: .milliseconds(150))

        await api.setFailing(["cpuMove"])
        var cell = await provider.move(for: game(), level: .cnn)
        #expect(game().board[cell] == nil)
        #expect(session.notice?.contains("Level 3 unavailable") == true)

        await api.setFailing([])
        await api.setCPUMoveReply(CPUMoveResponse(row: 0, col: 0))   // occupied
        cell = await provider.move(for: game(), level: .cnn)
        #expect(game().board[cell] == nil)

        await api.setDelay("cpuMove", .seconds(2))
        let started = ContinuousClock.now
        cell = await provider.move(for: game(), level: .cnn)
        #expect(game().board[cell] == nil)
        #expect(ContinuousClock.now - started < .seconds(1))
    }
}

@MainActor
struct AccountStoreTests {
    @Test func restoresASignedInSessionFromAStoredToken() async throws {
        let api = SpyAPI()
        await api.setAuthenticated(true)
        let backend = Backend.test(api: api, token: "stored")
        let accounts = AccountStore(backend: backend)
        await accounts.restore()
        #expect(accounts.account.isSignedIn)
        #expect(accounts.account.displayName == "ian")
        #expect(await api.calls == ["checkAuth", "profile"])
    }

    @Test func ensureIdentityWaitsForTheRestorePassInsteadOfMintingAGuest() async throws {
        // Opening a room right after launch, while the stored user token is still being checked,
        // must not call create_guest (the server answers 409 already_signed_in to a user token).
        let api = SpyAPI()
        await api.setAuthenticated(true)
        await api.setDelay("checkAuth", .milliseconds(100))
        let backend = Backend.test(api: api, token: "stored")
        let accounts = AccountStore(backend: backend)
        async let restoring: () = accounts.restore()
        try await Task.sleep(for: .milliseconds(10))
        let identity = try await accounts.ensureIdentity()
        await restoring
        #expect(accounts.account.isSignedIn)
        #expect(identity.displayName == "ian")
        #expect(!(await api.calls.contains("createGuest")))
    }

    @Test func anExpiredTokenIsDroppedWithoutAnAuthCallAndAGuestIsMinted() async throws {
        let api = SpyAPI()
        let backend = Backend.test(api: api, token: fakeJWT(expiringAt: Date().addingTimeInterval(-60)))
        let accounts = AccountStore(backend: backend)
        await accounts.restore()
        #expect(!accounts.account.isSignedIn)
        #expect(backend.tokenStore.accessToken() == nil)
        #expect(await api.calls == ["createGuest"])
        #expect(accounts.account.serverPlayerID == "guest-uuid")
    }

    @Test func aRejectedTokenFallsBackToGuest() async throws {
        let api = SpyAPI()
        await api.setAuthenticated(false)
        let backend = Backend.test(api: api, token: fakeJWT(expiringAt: Date().addingTimeInterval(3600)))
        let accounts = AccountStore(backend: backend)
        await accounts.restore()
        #expect(!accounts.account.isSignedIn)
        #expect(backend.tokenStore.accessToken() == nil)
    }

    @Test func signInStoresTheTokenAndSignOutClearsIt() async throws {
        let api = SpyAPI()
        let backend = Backend.test(api: api)
        let accounts = AccountStore(backend: backend)
        await #expect(throws: AuthError.invalidCredentials) {
            try await accounts.signIn(emailOrUsername: "ian", password: "wrong")
        }
        try await accounts.signIn(emailOrUsername: "ian", password: "secret")
        #expect(backend.tokenStore.accessToken() == "spy-token")
        #expect(accounts.account.profile?.email == "ian@example.com")
        await accounts.signOut()
        #expect(backend.tokenStore.accessToken() == nil)
        #expect(!accounts.account.isSignedIn)
    }

    @Test func sessionEndedClearsTheTokenOnceAndNotifies() async throws {
        let api = SpyAPI()
        let backend = Backend.test(api: api, token: "stored")
        let accounts = AccountStore(backend: backend)
        var reasons: [SessionEndReason] = []
        accounts.onSessionEnded = { reasons.append($0) }
        backend.sessions.post(.revoked)
        backend.sessions.post(.revoked)   // the same dead token again: ignored
        try await Task.sleep(for: .milliseconds(50))
        #expect(reasons == [.revoked])
        #expect(backend.tokenStore.accessToken() == nil)
        #expect(!accounts.account.isSignedIn)
    }

    @Test func disabledAccountsAreToldApart() async throws {
        let api = SpyAPI()
        await api.setFailure("login", status: 403, detail: "account_disabled")
        let accounts = AccountStore(backend: Backend.test(api: api))
        await #expect(throws: AuthError.accountDisabled) {
            try await accounts.signIn(emailOrUsername: "ian", password: "secret")
        }
        #expect(APIError.http(status: 401, body: #"{"detail":"session_revoked"}"#).sessionEndReason == .revoked)
        #expect(APIError.http(status: 401, body: #"{"detail":"Invalid credentials"}"#).sessionEndReason == nil)
        #expect(APIError.http(status: 403, body: #"{"detail":"account_disabled"}"#).sessionEndReason == nil)
    }

    @Test func deleteAccountSignsOutLocally() async throws {
        let api = SpyAPI()
        let backend = Backend.test(api: api, token: "stored")
        let accounts = AccountStore(backend: backend)
        try await accounts.deleteAccount(appleAuthorizationCode: "apple-code")
        #expect(await api.calls == ["deleteAccount", "createGuest"], "the device goes on as a guest")
        #expect(await api.deleteRequests == [AccountDeleteRequest(appleAuthorizationCode: "apple-code")])
        #expect(backend.tokenStore.accessToken() == nil)
        #expect(!accounts.account.isSignedIn)
        #expect(accounts.account.serverPlayerID == "guest-uuid")
    }

    @Test func deleteAccountFailureKeepsTheSession() async throws {
        let api = SpyAPI()
        await api.setFailing(["deleteAccount"])
        let backend = Backend.test(api: api, token: "stored")
        let accounts = AccountStore(backend: backend)
        await #expect(throws: AuthError.server(status: 500)) {
            try await accounts.deleteAccount()
        }
        #expect(backend.tokenStore.accessToken() == "stored")
    }

    @Test func passwordResetErrorsMapToCopy() async throws {
        let api = SpyAPI()
        let accounts = AccountStore(backend: Backend.test(api: api))
        await api.setFailure("requestPasswordReset", status: 429, detail: "Rate limit exceeded")
        await #expect(throws: AuthError.tooManyAttempts) {
            try await accounts.requestPasswordReset(email: "a@b.c")
        }
        await api.setFailure("resetPassword", status: 400, detail: "reset_token_expired")
        await #expect(throws: AuthError.resetLinkInvalid) {
            try await accounts.resetPassword(token: "t", newPassword: "longenough1")
        }
        await api.setFailure("resetPassword", status: 422, detail: "String should have at least 8 characters")
        await #expect(throws: AuthError.weakPassword("String should have at least 8 characters")) {
            try await accounts.resetPassword(token: "t", newPassword: "short")
        }
    }

    @Test func providerSignInSkipsTheBrowserForTheAppScheme() async throws {
        let api = SpyAPI()
        let backend = Backend.test(api: api)
        let accounts = AccountStore(backend: backend)
        var browserOpened = false
        try await accounts.signInWithProvider(.google) { _, _ in
            browserOpened = true
            return URL(string: "squareoff://auth?token=never")!
        }
        #expect(!browserOpened)
        #expect(backend.tokenStore.accessToken() == "spy-token")
        #expect(accounts.account.isSignedIn)
    }

    @Test func providerSignInUsesTheBrowserForWebURLs() async throws {
        let api = SpyAPI()
        await api.setOAuthURL(URL(string: "https://accounts.google.com/o/oauth2/auth")!)
        let backend = Backend.test(api: api)
        let accounts = AccountStore(backend: backend)
        try await accounts.signInWithProvider(.github) { url, scheme in
            #expect(url.host() == "accounts.google.com" && scheme == "squareoff")
            return URL(string: "squareoff://auth?token=from-browser")!
        }
        #expect(backend.tokenStore.accessToken() == "from-browser")
    }
}

struct ConfigurationTests {
    @Test func engineTiersPlaySixToTwelveOnly() {
        #expect(CPUAvailability.isSelectable(.impossible, boardSize: 8))
        #expect(CPUAvailability.isSelectable(.grandmaster, boardSize: 12))
        #expect(!CPUAvailability.isSelectable(.grandmaster, boardSize: 4))
        #expect(CPUAvailability.isSelectable(.maxMinPlus, boardSize: 4))
        #expect(CPUAvailability.unavailableLevels(boardSize: 5) == [.grandmaster, .impossible])
        #expect(CPUAvailability.unavailableLevels(boardSize: 8).isEmpty)
        #expect(CPUAvailability.footnote(kind: .production, level: .impossible).contains("Square Off server"))
        #expect(CPUAvailability.footnote(kind: .production, level: .maxMin) == "Levels 1–6 play on this device.")
    }

    @Test func launchArgumentBeatsThePersistedBackend() {
        let defaults = UserDefaults(suiteName: "SquareOffTests.config.\(UUID().uuidString)")!
        #expect(BackendConfiguration.load(from: defaults).kind == .mock)
        var live = BackendConfiguration.localDocker
        live.cpuMovesFromServer = true
        live.save(to: defaults)
        let loaded = BackendConfiguration.load(from: defaults)
        #expect(loaded.kind == .local && loaded.cpuMovesFromServer)
        defaults.setVolatileDomain(["backend": "mock"], forName: UserDefaults.argumentDomain)
        #expect(BackendConfiguration.load(from: defaults).kind == .mock)
        defaults.setVolatileDomain(["backend": "production"], forName: UserDefaults.argumentDomain)
        #expect(BackendConfiguration.load(from: defaults).kind == .production)
        defaults.setVolatileDomain([:], forName: UserDefaults.argumentDomain)
    }

    @Test func productionEnvironment() {
        let env = APIEnvironment.production
        #expect(env.baseURL.host() == "square-off.com" && env.baseURL.path() == "/api")
        #expect(env.webSocketURL.scheme == "wss" && env.webSocketURL.path() == "/ws")
        #expect(env.webOrigin.absoluteString == "https://square-off.com")
        #expect(BackendConfiguration.production.id == "production|square-off.com")
    }

    @Test func releaseBuildsOnlyLoadProduction() {
        let defaults = UserDefaults(suiteName: "SquareOffTests.config.\(UUID().uuidString)")!
        BackendConfiguration.mock.save(to: defaults)
        #expect(BackendConfiguration.load(from: defaults, available: [.production]).kind == .production)
        defaults.setVolatileDomain(["backend": "local"], forName: UserDefaults.argumentDomain)
        #expect(BackendConfiguration.load(from: defaults, available: [.production]).kind == .production)
        defaults.setVolatileDomain([:], forName: UserDefaults.argumentDomain)
    }

    @Test func liveAliasMapsToTheDockerStack() {
        #expect(BackendKind(persisted: "live") == .local)
        #expect(BackendKind(persisted: "production") == .production)
        #expect(BackendKind(persisted: "nope") == nil)
        let defaults = UserDefaults(suiteName: "SquareOffTests.config.\(UUID().uuidString)")!
        defaults.set("live", forKey: BackendConfiguration.Keys.kind)
        #expect(BackendConfiguration.load(from: defaults).kind == .local)
    }

    @Test func inviteLinksPointAtProductionExceptForLocalDocker() {
        #expect(BackendConfiguration.production.inviteOrigin.host() == "square-off.com")
        #expect(BackendConfiguration.mock.inviteOrigin.host() == "square-off.com")
        #expect(BackendConfiguration.localDocker.inviteOrigin.host() == "localhost")
    }

    @Test func jwtExpiryParsing() {
        let soon = Date().addingTimeInterval(120)
        #expect(JWT.expiry(of: fakeJWT(expiringAt: soon))!.timeIntervalSince(soon) < 1)
        #expect(JWT.isExpired(fakeJWT(expiringAt: Date().addingTimeInterval(-1))))
        #expect(!JWT.isExpired("not-a-jwt"))
    }
}

/// The device's guest session: minted on a fresh install, renewed when old, replaced when the
/// server drops it, never touched while a user is signed in.
@MainActor
struct GuestSessionTests {
    @Test func aFreshInstallMintsAGuestOnceAcrossRestores() async throws {
        let api = SpyAPI()
        let backend = Backend.test(api: api)
        let accounts = AccountStore(backend: backend)
        await accounts.restore()
        await accounts.restore()
        #expect(await api.calls == ["createGuest"])
        #expect(backend.guestTokens.accessToken() == "spy-guest-token-1")
        #expect(backend.identity.guest?.playerID == "guest-uuid")
        #expect(backend.tokens.accessToken() == "spy-guest-token-1")
        #expect(backend.tokens.kind(of: "spy-guest-token-1") == .guest)
    }

    @Test func theUserTokenWinsOverTheGuestToken() async throws {
        let backend = Backend.test(api: SpyAPI(), token: "user-token", guestToken: "guest-token")
        #expect(backend.tokens.accessToken() == "user-token")
        #expect(backend.tokens.kind(of: "user-token") == .user)
        #expect(backend.tokens.kind(of: "guest-token") == .guest)
    }

    @Test func anOldGuestTokenIsRenewedKeepingNameAndColour() async throws {
        let api = SpyAPI()
        let backend = Backend.test(api: api)
        _ = try await backend.identity.ensureGuest(name: "Zed", colorHex: "#123456")
        try backend.guestTokens.store(fakeJWT(expiringAt: Date().addingTimeInterval(5 * 86_400)))
        #expect(backend.identity.needsRenewal)
        let renewed = try await backend.identity.ensureGuest()
        #expect(renewed.name == "Zed" && renewed.colorHex == "#123456")
        #expect(await api.calls.filter { $0 == "createGuest" }.count == 2)
        try backend.guestTokens.store(fakeJWT(expiringAt: Date().addingTimeInterval(29 * 86_400)))
        #expect(!backend.identity.needsRenewal)
        _ = try await backend.identity.ensureGuest()
        #expect(await api.calls.filter { $0 == "createGuest" }.count == 2)
    }

    @Test func concurrentCallersShareOneMint() async throws {
        let api = SpyAPI()
        await api.setDelay("createGuest", .milliseconds(100))
        let backend = Backend.test(api: api)
        async let a = backend.identity.ensureGuest()
        async let b = backend.identity.ensureGuest()
        let (first, second) = try await (a, b)
        #expect(first == second)
        #expect(await api.calls.filter { $0 == "createGuest" }.count == 1)
    }

    @Test func recoveryMintsANewGuestUnlessAUserIsSignedIn() async throws {
        let api = SpyAPI()
        let guest = Backend.test(api: api, guestToken: "dead-guest")
        #expect(await guest.recovery.run())
        #expect(guest.guestTokens.accessToken() == "spy-guest-token-1")
        #expect(await api.calls == ["createGuest"])

        let signedIn = Backend.test(api: SpyAPI(), token: "user-token", guestToken: "guest-token")
        #expect(await signedIn.recovery.run() == false)
        #expect(signedIn.guestTokens.accessToken() == "guest-token")
    }

    @Test func signOutAndSessionEndFallBackToAGuest() async throws {
        let api = SpyAPI()
        let backend = Backend.test(api: api)
        let accounts = AccountStore(backend: backend)
        try await accounts.signIn(emailOrUsername: "ian", password: "secret")
        await accounts.signOut()
        #expect(accounts.account.serverPlayerID == "guest-uuid")
        #expect(await api.calls.filter { $0 == "createGuest" }.count == 1)

        try await accounts.signIn(emailOrUsername: "ian", password: "secret")
        backend.sessions.post(.revoked)
        try await Task.sleep(for: .milliseconds(100))
        #expect(!accounts.account.isSignedIn)
        #expect(accounts.account.serverPlayerID == "guest-uuid")   // the fresh guest token was reused
        #expect(await api.calls.filter { $0 == "createGuest" }.count == 1)
    }

    @Test func legacySeatIDsAreDroppedAndTheGuestIdentityKept() async throws {
        let defaults = UserDefaults(suiteName: "SquareOffTests.identity.\(UUID().uuidString)")!
        let id = BackendConfiguration.standard(for: .local).id
        defaults.set(["a", "b", "c"], forKey: "localSeatIDs.\(id)")
        defaults.set(try JSONEncoder().encode(GuestIdentity(playerID: "old-guest", name: "Old", colorHex: "#ABCDEF")), forKey: "guestIdentity.\(id)")
        let api = SpyAPI()
        let backend = Backend.test(api: api, defaults: defaults)
        #expect(defaults.stringArray(forKey: "localSeatIDs.\(id)") == nil)
        #expect(backend.identity.guest?.playerID == "old-guest")
        // No token for the old id: the first use mints a session, carrying the name and colour over.
        let guest = try await backend.identity.ensureGuest()
        #expect(guest.playerID == "guest-uuid" && guest.name == "Old" && guest.colorHex == "#ABCDEF")
    }

    @Test func noCookiesEverOnTheSharedSession() {
        let configuration = Backend.test(api: SpyAPI()).urlSession.configuration
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.httpCookieAcceptPolicy == .never)
        #expect(configuration.httpCookieStorage == nil)
    }
}

@MainActor
struct EngineTierTests {
    private func game(timer: Int = 0) -> Game {
        var game = Game(boardSize: 8, players: [
            PlayerState(id: 1, name: "Me", colorHex: "#0583D2"),
            PlayerState(id: 2, name: "CPU", colorHex: "#FF3131", isCPU: true, cpuLevel: .impossible),
        ], timerSeconds: timer)
        try! game.place(at: Cell(row: 0, col: 0))
        return game
    }

    @Test func theBackendSendsOnlyTheEngineTiersToTheServer() {
        let backend = Backend.test(api: SpyAPI())
        let me = [SetupPlayer(id: 1, name: "Me", colorHex: "#0583D2")]
        #expect(backend.makeCPUProvider(config: GameConfig(mode: .cpu(.impossible), boardSize: 8, timerSeconds: 0, players: me), notices: SessionNoticeRelay()) is ServerCPUMoveProvider)
        #expect(backend.makeCPUProvider(config: GameConfig(mode: .cpu(.grandmaster), boardSize: 8, timerSeconds: 0, players: me), notices: SessionNoticeRelay()) is ServerCPUMoveProvider)
        #expect(backend.makeCPUProvider(config: GameConfig(mode: .cpu(.maxMinPlus), boardSize: 8, timerSeconds: 0, players: me), notices: SessionNoticeRelay()) is LocalCPUMoveProvider)
        let all = Backend.test(api: SpyAPI(), cpuMovesFromServer: true)
        #expect(all.makeCPUProvider(config: GameConfig(mode: .cpu(.random), boardSize: 8, timerSeconds: 0, players: me), notices: SessionNoticeRelay()) is ServerCPUMoveProvider)
    }

    @Test func theTimerIsForwardedAndAnEngineFallbackIsMentionedOnce() async throws {
        let api = SpyAPI()
        await api.setCPUMoveReply(CPUMoveResponse(row: 4, col: 4, engine: CPUEngineInfo(mode: "fallback", fallback: true, fallbackCpuType: "max-min-io")))
        let notices = SessionNoticeRelay()
        let session = GameSession(config: GameConfig(mode: .cpu(.impossible), boardSize: 8, timerSeconds: 20, players: [SetupPlayer(id: 1, name: "Me", colorHex: "#0583D2")]))
        notices.session = session
        let provider = ServerCPUMoveProvider(api: api, serverLevels: [.impossible], notices: notices)
        #expect(await provider.move(for: game(timer: 20), level: .impossible) == Cell(row: 4, col: 4))
        #expect(await api.cpuMoveRequests.first?.timer == 20)
        #expect(await api.cpuMoveRequests.first?.cpuType == "impossible")
        #expect(session.notice == "Server engine busy, playing a simpler move")
        session.notice = nil
        _ = await provider.move(for: game(timer: 20), level: .impossible)
        #expect(session.notice == nil, "once per game")
        #expect(await api.cpuMoveRequests.last?.timer == 20)
        _ = await provider.move(for: game(), level: .impossible)
        #expect(await api.cpuMoveRequests.last?.timer == nil)
    }

    @Test func anUnreachableEngineTierPlaysLevelSixOnDevice() async throws {
        let api = SpyAPI()
        await api.setFailing(["cpuMove"])
        let notices = SessionNoticeRelay()
        let session = GameSession(config: GameConfig(mode: .cpu(.grandmaster), boardSize: 8, timerSeconds: 0, players: [SetupPlayer(id: 1, name: "Me", colorHex: "#0583D2")]))
        notices.session = session
        let provider = ServerCPUMoveProvider(api: api, serverLevels: [.grandmaster], notices: notices)
        let cell = await provider.move(for: game(), level: .grandmaster)
        #expect(game().board[cell] == nil)
        #expect(session.notice == "Level 7 unavailable, using Level 6 on device")
    }
}

@MainActor
struct SignUpTests {
    @Test func registerDoesNotSignInAndReportsThePendingState() async throws {
        let api = SpyAPI()
        let backend = Backend.test(api: api)
        let accounts = AccountStore(backend: backend)
        let response = try await accounts.register(username: "ian", email: "ian@example.com", password: "longenough1", turnstileToken: "tok")
        #expect(response.verificationRequired)
        #expect(!accounts.account.isSignedIn)
        #expect(backend.tokenStore.accessToken() == nil)
        #expect(await api.calls == ["register"])
    }

    @Test func signUpAndVerificationErrorsMapToCopy() async throws {
        let api = SpyAPI()
        let accounts = AccountStore(backend: Backend.test(api: api))
        let cases: [(String, Int, String, AuthError)] = [
            ("register", 409, "already_registered", .alreadyRegistered),
            ("register", 400, "captcha_failed", .captchaFailed),
            ("register", 503, "captcha_unavailable", .captchaUnavailable),
            ("register", 400, "email_domain_blocked", .emailDomainBlocked),
            ("register", 400, "email_domain_unreachable", .emailDomainUnreachable),
        ]
        for (method, status, detail, expected) in cases {
            await api.setFailure(method, status: status, detail: detail)
            await #expect(throws: expected) {
                try await accounts.register(username: "ian", email: "ian@example.com", password: "longenough1")
            }
        }
        await api.setFailure("login", status: 403, detail: "email_unverified")
        await #expect(throws: AuthError.emailUnverified) {
            try await accounts.signIn(emailOrUsername: "ian", password: "secret")
        }
        await api.setFailure("verifyEmail", status: 400, detail: "verify_token_expired")
        await #expect(throws: AuthError.verifyLinkExpired) { _ = try await accounts.verifyEmail(token: "t") }
        await api.setFailure("verifyEmail", status: 400, detail: "verify_token_invalid")
        await #expect(throws: AuthError.verifyLinkInvalid) { _ = try await accounts.verifyEmail(token: "t") }
        await api.setFailure("resendVerification", status: 429, detail: "Rate limit exceeded")
        await #expect(throws: AuthError.tooManyAttempts) { try await accounts.resendVerification(email: "a@b.c") }
        #expect(AuthError.wrap(APIError.http(status: 401, body: #"{"detail":"account_required"}"#)) == .signInRequired)
    }

    @Test func turnstilePageIsProductionOnly() {
        #expect(BackendConfiguration.production.turnstilePageURL?.absoluteString == "https://square-off.com/turnstile?theme=dark")
        #expect(BackendConfiguration.mock.turnstilePageURL == nil)
        #expect(BackendConfiguration.localDocker.turnstilePageURL == nil)
    }
}
