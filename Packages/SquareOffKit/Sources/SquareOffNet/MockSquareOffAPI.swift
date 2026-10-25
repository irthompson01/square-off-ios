import Foundation
import SquareOffCore

/// In-memory simulation of the FastAPI server: users, guests, games, turns, stats and replays,
/// plus `cpuMove` computed with the real on-device heuristics. The app runs against it by
/// default so every flow works without docker. State lives for the process only.
///
/// Identity works like the live server: `login` returns a token (`mock:<username>`), and every
/// authenticated call reads it from the injected `TokenProvider` (or from the last login when
/// none is injected, which keeps simple test flows short).
public actor MockSquareOffAPI: SquareOffAPI {
    public static let demoUsername = "demo"
    public static let demoEmail = "demo@squareoff.app"
    public static let demoPassword = "password"
    public static let demoUserID = "11111111-1111-4111-8111-111111111111"
    public static let guestIDs = [
        "00000000-0000-0000-0000-000000000001",
        "00000000-0000-0000-0000-000000000002",
        "00000000-0000-0000-0000-000000000003",
        "00000000-0000-0000-0000-000000000004",
    ]

    public static func token(for username: String) -> String { "mock:\(username)" }

    struct User: Sendable {
        let id: String
        var username: String
        var email: String
        var password: String
        var firstName: String
        var lastName: String
        var color: String
        let createdAt: String
        var appRole = "standard"

        var profile: ProfileResponse {
            ProfileResponse(id: id, username: username, email: email, firstName: firstName,
                            lastName: lastName, color: color, createdAt: createdAt, appRole: appRole)
        }
    }

    struct Seat: Sendable {
        let id: Int
        var name: String
        var color: String
        var playerID: String?
        var isCPU: Bool
        var cpuType: String?
        var participantID: Int

        var participantType: String {
            if isCPU { return "cpu" }
            return playerID.map { $0.count == 36 || $0.hasPrefix("mock-user") ? "user" : "guest" } ?? "guest"
        }
    }

    struct GameRecord: Sendable {
        let id: Int
        let boardSize: Int
        let timer: Int
        let type: String
        var seats: [Seat]
        var turns: [GameTurnRequest] = []
        let startedAt: Date
        var endedAt: Date?
        var winnerID: String?
        var scores: [ScoreEntry] = []

        var isEnded: Bool { endedAt != nil }
        var cpuType: String? { seats.last(where: \.isCPU)?.cpuType }

        func seat(forParticipant participantID: Int?) -> Seat? {
            seats.first { $0.participantID == participantID }
        }

        func finalScore(of seat: Seat) -> Int {
            if let entry = scores.first(where: { $0.playerId == seat.playerID }) { return entry.score }
            return turns.last { $0.participantId == seat.participantID }?.currentScore ?? 0
        }
    }

    private var users: [User] = []
    private var guests: [String] = []
    private var games: [Int: GameRecord] = [:]
    private var nextGameID = 1
    private var nextTurnID = 1
    private var nextParticipantID = 1
    private var sessionToken: String?
    private var revokedTokens: Set<String> = []
    private var seeded = false
    private let shouldSeed: Bool
    private let latency: Duration
    private let tokenProvider: (any TokenProvider)?
    private let onSessionEnded: (@Sendable (SessionEndReason) -> Void)?

    public init(latency: Duration = .milliseconds(150), tokenProvider: (any TokenProvider)? = nil, seed: Bool = true,
                onSessionEnded: (@Sendable (SessionEndReason) -> Void)? = nil) {
        self.latency = latency
        self.tokenProvider = tokenProvider
        self.shouldSeed = seed
        self.onSessionEnded = onSessionEnded
    }

    /// Simulates an admin "Force sign-out" (or a bumped `session_version`): the current token
    /// answers 401 `session_revoked` from now on. Developer panel only.
    public func revokeSession() {
        if let token = tokenProvider?.accessToken() ?? sessionToken { revokedTokens.insert(token) }
    }

    // MARK: Auth

    public func guests() async throws -> GuestsResponse {
        try await pause()
        let newest = Array(guests.suffix(4).reversed())
        return GuestsResponse(guests: newest.isEmpty ? Self.guestIDs : newest)
    }

    public func cpuPlayer(_ level: CPULevel) async throws -> CPUPlayerResponse {
        try await pause()
        return CPUPlayerResponse(id: level.number, cpuType: level.cpuType,
                                 displayName: "CPU (\(level.shortName))", color: "#FF3131")
    }

    public func login(_ request: LoginRequest) async throws -> LoginResponse {
        try await pause()
        ensureSeeded()
        let key = request.emailOrUsername.lowercased()
        guard let user = users.first(where: { $0.username.lowercased() == key || $0.email.lowercased() == key }),
              user.password == request.password
        else { throw APIError.http(status: 401, body: #"{"detail":"Invalid credentials"}"#) }
        let token = Self.token(for: user.username)
        sessionToken = token
        return LoginResponse(message: "Login successful", accessToken: token)
    }

    public func register(_ request: RegisterRequest) async throws -> RegisterResponse {
        try await pause()
        ensureSeeded()
        let username = request.username.trimmingCharacters(in: .whitespaces)
        let email = request.email.trimmingCharacters(in: .whitespaces)
        guard !username.isEmpty, email.contains("@"), request.password.count >= 1 else {
            throw APIError.http(status: 422, body: #"{"detail":"Invalid registration"}"#)
        }
        guard !users.contains(where: { $0.username.lowercased() == username.lowercased() || $0.email.lowercased() == email.lowercased() }) else {
            throw APIError.http(status: 400, body: #"{"detail":"Username or email already registered"}"#)
        }
        let user = User(id: "mock-user-\(UUID().uuidString.lowercased())", username: username, email: email,
                        password: request.password, firstName: "", lastName: "", color: "#0583D2",
                        createdAt: Self.timestamp(Date()))
        users.append(user)
        return RegisterResponse(message: "User registered successfully", playerId: user.id)
    }

    public func logout() async throws {
        sessionToken = nil
    }

    public func checkAuth() async throws -> Bool {
        ensureSeeded()
        return (try? currentUser()) != nil
    }

    public func createGuest(_ request: CreateGuestRequest) async throws -> CreateGuestResponse {
        try await pause()
        let id = "mock-guest-\(UUID().uuidString.lowercased())"
        guests.append(id)
        return CreateGuestResponse(message: "Guest created", playerId: id)
    }

    public func profile() async throws -> ProfileResponse {
        try await pause()
        return try currentUser().profile
    }

    public func updateProfile(_ request: ProfileUpdateRequest) async throws {
        try await pause()
        let user = try currentUser()
        guard let index = users.firstIndex(where: { $0.id == user.id }) else { return }
        if let firstName = request.firstName { users[index].firstName = firstName }
        if let lastName = request.lastName { users[index].lastName = lastName }
        if let color = request.color { users[index].color = color }
    }

    public func oauthLoginURL(_ provider: OAuthProvider, client: OAuthClient) async throws -> OAuthLoginResponse {
        try await pause()
        ensureSeeded()
        switch client {
        case .ios:
            // The app recognises its own scheme and skips the browser entirely.
            sessionToken = Self.token(for: Self.demoUsername)
            return OAuthLoginResponse(url: URL(string: "squareoff://auth?token=\(Self.token(for: Self.demoUsername))")!, state: "mock")
        case .web:
            return OAuthLoginResponse(url: URL(string: "https://square-off.example/oauth/\(provider.rawValue)")!, state: "mock")
        }
    }

    public func appleNativeLogin(_ request: AppleNativeLoginRequest) async throws -> LoginResponse {
        try await pause()
        ensureSeeded()
        guard !request.identityToken.isEmpty else {
            throw APIError.http(status: 401, body: #"{"detail":"apple_invalid_token"}"#)
        }
        let token = Self.token(for: Self.demoUsername)
        sessionToken = token
        return LoginResponse(message: "Login successful", accessToken: token)
    }

    // MARK: Games

    public func startGame(_ request: StartGameRequest) async throws -> StartGameResponse {
        try await pause()
        ensureSeeded()
        return createGame(request, startedAt: Date())
    }

    public func insertTurn(gameID: Int, _ turn: GameTurnRequest) async throws -> GameTurnResponse {
        guard games[gameID] != nil else {
            throw APIError.http(status: 404, body: #"{"detail":"Game not found"}"#)
        }
        return appendTurn(gameID: gameID, turn)
    }

    public func updatePlayers(gameID: Int, players: [PlayerPayload]) async throws {
        try await pause()
        guard var game = games[gameID] else {
            throw APIError.http(status: 404, body: #"{"detail":"Game not found"}"#)
        }
        for payload in players {
            if let index = game.seats.firstIndex(where: { $0.id == payload.id }) {
                if let name = payload.name { game.seats[index].name = name }
                if let color = payload.fillStyle { game.seats[index].color = color }
                if let playerID = payload.playerId { game.seats[index].playerID = playerID }
            } else {
                game.seats.append(Seat(id: payload.id, name: payload.displayName, color: payload.colorHex,
                                       playerID: payload.playerId, isCPU: payload.isCPU ?? false,
                                       cpuType: payload.cpuType, participantID: nextParticipantID))
                nextParticipantID += 1
            }
        }
        games[gameID] = game
    }

    public func endGame(_ request: GameEndRequest) async throws {
        try await pause()
        guard games[request.gameId] != nil else {
            throw APIError.http(status: 404, body: #"{"detail":"Game not found"}"#)
        }
        guard games[request.gameId]?.isEnded == false else {
            throw APIError.http(status: 404, body: #"{"detail":"Game already ended"}"#)
        }
        finishGame(request, endedAt: Date())
    }

    public func replay(gameID: Int) async throws -> GameReplayPayload {
        try await pause()
        let user = try currentUser()
        guard let game = games[gameID] else {
            throw APIError.http(status: 404, body: #"{"detail":"Game not found"}"#)
        }
        guard game.isEnded, game.seats.contains(where: { $0.playerID == user.id }) else {
            throw APIError.http(status: 403, body: #"{"detail":"Replay not available"}"#)
        }
        return Self.replayPayload(for: game)
    }

    // MARK: Stats

    public func statsView() async throws -> PlayerStatsView {
        try await pause()
        let user = try currentUser()
        let mine = finishedGames(of: user)
        let outcomes = mine.map { outcome(of: $0, for: user) }
        let wins = outcomes.filter { $0.result == "W" }.count
        return PlayerStatsView(
            playerId: user.id, username: user.username, email: user.email, firstName: user.firstName,
            lastName: user.lastName, color: user.color, createdAt: user.createdAt,
            totalGamesPlayed: mine.count, gamesWon: wins, gamesLost: mine.count - wins,
            winPercentage: Self.percentage(wins, of: mine.count),
            avgGameDuration: Self.averageMinutes(mine),
            highestScore: outcomes.map(\.myScore).max() ?? 0,
            avgFinalScore: Self.average(outcomes.map(\.myScore)),
            localGamesPlayed: mine.filter { $0.type == "local" }.count
        )
    }

    public func statsViewCPU(boardSize: Int?, timer: Int?, cpuType: String?) async throws -> [PlayerStatsCPUView] {
        try await pause()
        let user = try currentUser()
        let mine = finishedGames(of: user).filter { game in
            guard let type = game.cpuType else { return false }
            if let boardSize, game.boardSize != boardSize { return false }
            if let timer, game.timer != timer { return false }
            if let cpuType, !cpuType.isEmpty, type != cpuType { return false }
            return true
        }
        let grouped = Dictionary(grouping: mine) { $0.cpuType ?? "" }
        return grouped.keys.sorted().map { type in
            let games = grouped[type] ?? []
            let outcomes = games.map { outcome(of: $0, for: user) }
            let wins = outcomes.filter { $0.result == "W" }.count
            let level = CPULevel(rawValue: type)
            return PlayerStatsCPUView(
                playerId: "cpu-\(type)", username: "CPU (\(level?.shortName ?? type))", cpuType: type,
                totalGamesPlayed: games.count, gamesWon: wins, gamesLost: games.count - wins,
                winPercentage: Self.percentage(wins, of: games.count),
                avgGameDuration: Self.averageMinutes(games),
                highestScore: outcomes.map(\.myScore).max() ?? 0,
                avgFinalScore: Self.average(outcomes.map(\.myScore)),
                localGamesPlayed: games.filter { $0.type == "local" }.count
            )
        }
    }

    public func statsViewHuman(boardSize: Int?, timer: Int?) async throws -> PlayerStatsView {
        try await pause()
        let user = try currentUser()
        let mine = finishedGames(of: user).filter { game in
            guard game.cpuType == nil else { return false }
            if let boardSize, game.boardSize != boardSize { return false }
            if let timer, game.timer != timer { return false }
            return true
        }
        let outcomes = mine.map { outcome(of: $0, for: user) }
        let wins = outcomes.filter { $0.result == "W" }.count
        return PlayerStatsView(
            playerId: user.id, username: user.username, email: user.email, firstName: user.firstName,
            lastName: user.lastName, color: user.color, createdAt: user.createdAt,
            totalGamesPlayed: mine.count, gamesWon: wins, gamesLost: mine.count - wins,
            winPercentage: Self.percentage(wins, of: mine.count),
            avgGameDuration: Self.averageMinutes(mine),
            highestScore: outcomes.map(\.myScore).max() ?? 0,
            avgFinalScore: Self.average(outcomes.map(\.myScore)),
            localGamesPlayed: mine.filter { $0.type == "local" }.count
        )
    }

    public func profileStatsFilters(scope: String) async throws -> ProfileStatsFilters {
        try await pause()
        let user = try currentUser()
        let mine = finishedGames(of: user).filter { scope == "cpu" ? $0.cpuType != nil : $0.cpuType == nil }
        return ProfileStatsFilters(
            boardSizes: Array(Set(mine.map(\.boardSize))).sorted(),
            timers: Array(Set(mine.map(\.timer))).sorted(),
            cpuTypes: scope == "cpu" ? Array(Set(mine.compactMap(\.cpuType))).sorted() : []
        )
    }

    public func recentGames(limit: Int, offset: Int) async throws -> RecentGamesPage {
        try await pause()
        let user = try currentUser()
        let mine = finishedGames(of: user)
        let page = mine.dropFirst(max(offset, 0)).prefix(max(limit, 1))
        let rows = page.map { game -> RecentGameRow in
            let outcome = outcome(of: game, for: user)
            return RecentGameRow(gameId: game.id, gameType: game.type, opponentLabel: outcome.opponent,
                                 myScore: outcome.myScore, result: outcome.result)
        }
        return RecentGamesPage(games: rows, total: mine.count)
    }

    // MARK: Model

    /// Rebuilds the position and answers with the real heuristic for `cpu_type`. "cnn" plays as
    /// Max-Min-Optimal, the strategy the CNN was trained on. Same quirk as the server: the mover
    /// is the first `isCPU` seat.
    public func cpuMove(_ request: CPUMoveRequest) async throws -> CPUMoveResponse {
        try await Task.sleep(for: .milliseconds(300))
        guard let game = Self.game(from: request) else {
            throw APIError.http(status: 400, body: #"{"detail":"Invalid board state"}"#)
        }
        let level = CPULevel(rawValue: request.cpuType.lowercased()) ?? .maxRandom
        let strategy = CPUStrategy(level: level.offlineFallback) ?? .maxMinOptimal
        let cell = strategy.chooseMove(in: game)
        return CPUMoveResponse(row: cell.row, col: cell.col)
    }

    static func game(from request: CPUMoveRequest) -> Game? {
        let size = request.boardState.count
        guard size >= 2, request.boardState.allSatisfy({ $0.count == size }) else { return nil }
        var board = Board(size: size)
        for row in 0..<size {
            for col in 0..<size {
                board[row, col] = request.boardState[row][col]?.id
            }
        }
        let players = request.gamePlayers.map { seat -> PlayerState in
            var player = PlayerState(id: seat.id, name: seat.name, colorHex: seat.fillStyle, isCPU: seat.isCPU,
                                     cpuLevel: seat.cpuType.flatMap(CPULevel.init(rawValue:)),
                                     serverPlayerID: seat.playerId, participantID: seat.participantId)
            player.score = seat.currentScore
            player.multiplier = seat.currentMultiplier
            player.squares = seat.squares.map { $0.boardShape(kind: .square, ownerID: seat.id) }
            player.diamonds = seat.diamonds.map { $0.boardShape(kind: .diamond, ownerID: seat.id) }
            return player
        }
        guard (2...4).contains(players.count), Set(players.map(\.id)).count == players.count,
              players.allSatisfy({ (1...4).contains($0.id) }) else { return nil }
        let mover = players.firstIndex(where: \.isCPU) ?? players.firstIndex { $0.id == request.currentPlayer.id } ?? 0
        return Game(board: board, players: players, currentPlayerIndex: mover)
    }

    // MARK: Internals

    private func pause() async throws {
        if latency > .zero { try await Task.sleep(for: latency) }
    }

    private func currentUser() throws -> User {
        let token = tokenProvider?.accessToken() ?? sessionToken
        if let token, revokedTokens.contains(token) {
            onSessionEnded?(.revoked)
            throw APIError.http(status: 401, body: #"{"detail":"session_revoked"}"#)
        }
        guard let token, token.hasPrefix("mock:"),
              let user = users.first(where: { $0.username == String(token.dropFirst(5)) })
        else { throw APIError.http(status: 401, body: #"{"detail":"Not authenticated"}"#) }
        return user
    }

    private func createGame(_ request: StartGameRequest, startedAt: Date) -> StartGameResponse {
        let id = nextGameID
        nextGameID += 1
        let seats = request.players.map { player -> Seat in
            defer { nextParticipantID += 1 }
            return Seat(id: player.id, name: player.name, color: player.color, playerID: player.playerId,
                        isCPU: player.isCPU, cpuType: player.cpuType, participantID: nextParticipantID)
        }
        games[id] = GameRecord(id: id, boardSize: request.boardSize, timer: request.timer, type: request.type,
                               seats: seats, startedAt: startedAt)
        return StartGameResponse(gameId: id, participants: seats.map {
            StartGameResponse.Participant(playerId: $0.playerID ?? String($0.id), participantId: $0.participantID)
        })
    }

    @discardableResult
    private func appendTurn(gameID: Int, _ turn: GameTurnRequest) -> GameTurnResponse {
        games[gameID]?.turns.append(turn)
        defer { nextTurnID += 1 }
        return GameTurnResponse(turnId: nextTurnID)
    }

    private func finishGame(_ request: GameEndRequest, endedAt: Date) {
        games[request.gameId]?.endedAt = endedAt
        games[request.gameId]?.winnerID = request.winnerId
        games[request.gameId]?.scores = request.scores
    }

    private func finishedGames(of user: User) -> [GameRecord] {
        games.values
            .filter { $0.isEnded && $0.seats.contains { $0.playerID == user.id } }
            .sorted { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) }
    }

    private func outcome(of game: GameRecord, for user: User) -> (myScore: Int, result: String, opponent: String) {
        let mine = game.seats.first { $0.playerID == user.id }
        let myScore = mine.map(game.finalScore) ?? 0
        let result: String
        if game.winnerID == user.id { result = "W" } else if game.winnerID == "" { result = "T" } else { result = "L" }
        let others = game.seats.filter { $0.playerID != user.id }.map { seat -> String in
            if seat.isCPU { return "CPU (\(seat.cpuType ?? "cpu"))" }
            return seat.participantType == "user" ? seat.name : "Guest"
        }
        return (myScore, result, others.isEmpty ? "—" : others.joined(separator: ", "))
    }

    static func replayPayload(for game: GameRecord) -> GameReplayPayload {
        let participants = game.seats.map {
            ReplayParticipant(participantId: $0.participantID, boardSlotId: $0.id, displayName: $0.name,
                              color: $0.color, participantType: $0.participantType, cpuType: $0.cpuType)
        }
        let turns = game.turns.enumerated().compactMap { index, turn -> ReplayTurn? in
            let seat = game.seat(forParticipant: turn.participantId)
                ?? game.seats.first { $0.playerID == turn.playerId && !turn.playerId.isEmpty }
            guard let seat else { return nil }
            return ReplayTurn(turnNumber: index + 1, boardSlotId: seat.id, rowIndex: turn.rowIndex, colIndex: turn.colIndex)
        }
        return GameReplayPayload(gameId: game.id, boardSize: game.boardSize, timer: game.timer, gameType: game.type,
                                 participants: participants, turns: turns)
    }

    static func percentage(_ part: Int, of total: Int) -> Double {
        guard total > 0 else { return 0 }
        return (Double(part) / Double(total) * 10000).rounded() / 100
    }

    static func average(_ values: [Int]) -> Double {
        guard !values.isEmpty else { return 0 }
        return (Double(values.reduce(0, +)) / Double(values.count)).rounded()
    }

    static func averageMinutes(_ games: [GameRecord]) -> Double {
        let durations = games.compactMap { game -> Double? in
            guard let end = game.endedAt else { return nil }
            return end.timeIntervalSince(game.startedAt) / 60
        }
        guard !durations.isEmpty else { return 0 }
        return (durations.reduce(0, +) / Double(durations.count)).rounded()
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return String(formatter.string(from: date).dropLast()) // server emits no zone suffix
    }

    // MARK: Seed data

    /// The demo account plus three finished games played by the real heuristics, so stats and
    /// replays show something on first launch.
    private func ensureSeeded() {
        guard shouldSeed, !seeded else { return }
        seeded = true
        let demo = User(id: Self.demoUserID, username: Self.demoUsername, email: Self.demoEmail,
                        password: Self.demoPassword, firstName: "Demo", lastName: "Player", color: "#0583D2",
                        createdAt: "2026-09-01T12:00:00")
        users.append(demo)
        var rng = SplitMix64(seed: 0x5EED_5EED)
        let now = Date()
        seedGame(boardSize: 8, timer: 0, startedAt: now.addingTimeInterval(-3 * 86_400), minutes: 7,
                 seats: [(StartPlayer(id: 1, name: "Demo", color: "#0583D2", playerId: demo.id, isCPU: false, cpuType: nil), .maxMinOptimal),
                         (StartPlayer(id: 2, name: "CPU (max-min)", color: "#FF3131", playerId: "4", isCPU: true, cpuType: "max-min"), .maxMin)],
                 rng: &rng)
        seedGame(boardSize: 8, timer: 20, startedAt: now.addingTimeInterval(-2 * 86_400), minutes: 5,
                 seats: [(StartPlayer(id: 1, name: "Demo", color: "#0583D2", playerId: demo.id, isCPU: false, cpuType: nil), .maxRandom),
                         (StartPlayer(id: 2, name: "CPU (cnn)", color: "#FF3131", playerId: "1", isCPU: true, cpuType: "cnn"), .maxMinOptimal)],
                 rng: &rng)
        seedGame(boardSize: 6, timer: 0, startedAt: now.addingTimeInterval(-86_400), minutes: 4,
                 seats: [(StartPlayer(id: 1, name: "Demo", color: "#0583D2", playerId: demo.id, isCPU: false, cpuType: nil), .maxMin),
                         (StartPlayer(id: 2, name: "Guest", color: "#FF3131", playerId: Self.guestIDs[1], isCPU: false, cpuType: nil), .random),
                         (StartPlayer(id: 3, name: "Guest", color: "#50C878", playerId: Self.guestIDs[2], isCPU: false, cpuType: nil), .maxRandom)],
                 rng: &rng)
    }

    private func seedGame(boardSize: Int, timer: Int, startedAt: Date, minutes: Double,
                          seats: [(StartPlayer, CPUStrategy)], rng: inout SplitMix64) {
        let start = createGame(StartGameRequest(boardSize: boardSize, timer: timer, seats: seats.map(\.0), type: .local), startedAt: startedAt)
        var game = Game(boardSize: boardSize, players: seats.map { seat, _ in
            PlayerState(id: seat.id, name: seat.name, colorHex: seat.color, isCPU: seat.isCPU,
                        cpuLevel: seat.cpuType.flatMap(CPULevel.init(rawValue:)), serverPlayerID: seat.playerId)
        })
        let participants = Dictionary(uniqueKeysWithValues: zip(seats.map(\.0.id), start.participants.map(\.participantId)))
        while !game.isOver {
            let mover = game.currentPlayer
            let strategy = seats.first { $0.0.id == mover.id }?.1 ?? .random
            let cell = strategy.chooseMove(in: game, using: &rng)
            guard let move = try? game.place(at: cell) else { break }
            appendTurn(gameID: start.gameId, GameTurnRequest(move: move, player: mover, playerID: mover.serverPlayerID,
                                                              participantID: participants[mover.id]))
        }
        let winner = game.isDraw ? "" : (game.standings.first?.serverPlayerID ?? "")
        finishGame(GameEndRequest(gameId: start.gameId, winnerId: winner,
                                  scores: game.players.map { ScoreEntry(playerId: $0.serverPlayerID ?? String($0.id), score: $0.score) }),
                   endedAt: startedAt.addingTimeInterval(minutes * 60))
    }
}
