import Foundation
import SquareOffCore

// Wire types for the FastAPI server. Field names match exactly what the web client sends
// (hero-client/src/services/*.ts) — snake_case at the top level, camelCase inside `players`
// because the web serialises its `Player` objects as-is and the server maps both spellings.

// MARK: Auth

public struct GuestsResponse: Codable, Sendable, Equatable {
    public let guests: [String]

    public init(guests: [String]) { self.guests = guests }
}

public struct CPUPlayerResponse: Codable, Sendable, Equatable {
    public let id: Int
    public let cpuType: String
    public let displayName: String
    public let color: String?

    public init(id: Int, cpuType: String, displayName: String, color: String?) {
        self.id = id
        self.cpuType = cpuType
        self.displayName = displayName
        self.color = color
    }

    enum CodingKeys: String, CodingKey {
        case id, color
        case cpuType = "cpu_type"
        case displayName = "display_name"
    }
}

public struct LoginRequest: Codable, Sendable, Equatable {
    public let emailOrUsername: String
    public let password: String

    public init(emailOrUsername: String, password: String) {
        self.emailOrUsername = emailOrUsername
        self.password = password
    }

    enum CodingKeys: String, CodingKey {
        case emailOrUsername = "email_or_username"
        case password
    }
}

public struct RegisterRequest: Codable, Sendable, Equatable {
    public let username: String
    public let email: String
    public let password: String
    public let registered: Bool

    public init(username: String, email: String, password: String) {
        self.username = username
        self.email = email
        self.password = password
        self.registered = true
    }
}

/// `POST /password/forgot`. The server always answers 200 with the same message.
public struct PasswordForgotRequest: Codable, Sendable, Equatable {
    public let email: String

    public init(email: String) { self.email = email }
}

/// `POST /password/reset`; `new_password` must be at least 8 characters.
public struct PasswordResetRequest: Codable, Sendable, Equatable {
    public let token: String
    public let newPassword: String

    public init(token: String, newPassword: String) {
        self.token = token
        self.newPassword = newPassword
    }

    enum CodingKeys: String, CodingKey {
        case token
        case newPassword = "new_password"
    }
}

/// `POST /account/delete`. A fresh Sign in with Apple authorization code lets the server revoke
/// the Apple session too; omitted for other sign-in methods.
public struct AccountDeleteRequest: Codable, Sendable, Equatable {
    public let appleAuthorizationCode: String?

    public init(appleAuthorizationCode: String? = nil) { self.appleAuthorizationCode = appleAuthorizationCode }

    enum CodingKeys: String, CodingKey {
        case appleAuthorizationCode = "apple_authorization_code"
    }
}

/// `POST /feedback` (web `feedbackAPI.ts`): subject 1–200, message 1–20000, optional name
/// (≤ 200) and contact email. Empty optionals are sent as `null`, like the web.
public struct FeedbackRequest: Codable, Sendable, Equatable {
    public static let subjectLimit = 200
    public static let messageLimit = 20_000
    public static let nameLimit = 200

    public let subject: String
    public let message: String
    public let contactEmail: String?
    public let displayName: String?

    public init(subject: String, message: String, contactEmail: String? = nil, displayName: String? = nil) {
        self.subject = subject
        self.message = message
        self.contactEmail = contactEmail
        self.displayName = displayName
    }

    enum CodingKeys: String, CodingKey {
        case subject, message
        case contactEmail = "contact_email"
        case displayName = "display_name"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(subject, forKey: .subject)
        try c.encode(message, forKey: .message)
        try c.encode(contactEmail, forKey: .contactEmail)
        try c.encode(displayName, forKey: .displayName)
    }
}

/// `{"message", "id", "emailed"}` from `POST /feedback` (`id` is null when only the email went out).
public struct FeedbackResponse: Codable, Sendable, Equatable {
    public let message: String
    public let id: Int?
    public let emailed: Bool?

    public init(message: String, id: Int? = nil, emailed: Bool? = nil) {
        self.message = message
        self.id = id
        self.emailed = emailed
    }
}

/// `{"message": …}` and whatever else a simple write answers with.
public struct MessageResponse: Codable, Sendable, Equatable {
    public let message: String

    public init(message: String) { self.message = message }
}

// MARK: Games

/// One seat in `POST /start` (`players[]`), same keys as the web's setup page builds.
public struct StartPlayer: Codable, Sendable, Equatable {
    public let id: Int
    public let name: String
    public let color: String
    public let playerId: String?
    public let isCPU: Bool
    public let cpuType: String?

    public init(_ player: PlayerState) {
        self.init(seat: player, playerID: player.serverPlayerID)
    }

    /// The recorder owns the seat → server id map, so it passes the id explicitly.
    public init(seat player: PlayerState, playerID: String?) {
        id = player.id
        name = player.name
        color = player.colorHex
        playerId = playerID
        isCPU = player.isCPU
        cpuType = player.cpuLevel?.cpuType
    }

    public init(id: Int, name: String, color: String, playerId: String?, isCPU: Bool, cpuType: String?) {
        self.id = id
        self.name = name
        self.color = color
        self.playerId = playerId
        self.isCPU = isCPU
        self.cpuType = cpuType
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(color, forKey: .color)
        try c.encode(playerId, forKey: .playerId)
        try c.encode(isCPU, forKey: .isCPU)
        try c.encode(cpuType, forKey: .cpuType)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, color, playerId, isCPU, cpuType
    }
}

public struct StartGameRequest: Codable, Sendable, Equatable {
    public let boardSize: Int
    public let timer: Int
    public let players: [StartPlayer]
    public let type: String
    public let isCPU: Bool
    public let cpuType: String?

    /// Mirrors `gameAPI.startGame`: `is_cpu`/`cpu_type` come from the (last) CPU seat.
    public init(boardSize: Int, timer: Int, players: [PlayerState], type: GameType) {
        self.init(boardSize: boardSize, timer: timer, seats: players.map(StartPlayer.init), type: type)
    }

    public init(boardSize: Int, timer: Int, seats: [StartPlayer], type: GameType) {
        self.boardSize = boardSize
        self.timer = timer
        self.players = seats
        self.type = type.rawValue
        let cpu = seats.last(where: \.isCPU)
        self.isCPU = cpu != nil
        self.cpuType = cpu?.cpuType
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(boardSize, forKey: .boardSize)
        try c.encode(timer, forKey: .timer)
        try c.encode(players, forKey: .players)
        try c.encode(type, forKey: .type)
        try c.encode(isCPU, forKey: .isCPU)
        try c.encode(cpuType, forKey: .cpuType)
    }

    enum CodingKeys: String, CodingKey {
        case timer, players, type
        case boardSize = "board_size"
        case isCPU = "is_cpu"
        case cpuType = "cpu_type"
    }
}

public enum GameType: String, Codable, Sendable {
    case local
    case online
}

public struct StartGameResponse: Codable, Sendable, Equatable {
    public struct Participant: Codable, Sendable, Equatable {
        public let playerId: String
        public let participantId: Int

        public init(playerId: String, participantId: Int) {
            self.playerId = playerId
            self.participantId = participantId
        }

        enum CodingKeys: String, CodingKey {
            case playerId = "player_id"
            case participantId = "participant_id"
        }
    }

    public let gameId: Int
    public let participants: [Participant]

    public init(gameId: Int, participants: [Participant]) {
        self.gameId = gameId
        self.participants = participants
    }

    enum CodingKeys: String, CodingKey {
        case gameId = "game_id"
        case participants
    }
}

/// `POST /{gameId}/turns` body, as built in `game-board.tsx`.
public struct GameTurnRequest: Codable, Sendable, Equatable {
    public let rowIndex: Int
    public let colIndex: Int
    public let playerId: String
    public let currentScore: Int
    public let currentMultiplier: Int
    public let multiplierIncrease: Int
    public let scoreIncrease: Int
    public let newDiamondCount: Int
    public let newSquareCount: Int
    public let isCPU: Bool
    public let cpuType: String?
    public let participantId: Int?

    public init(move: MoveResult, player: PlayerState) {
        self.init(move: move, player: player, playerID: player.serverPlayerID, participantID: player.participantID)
    }

    /// Server ids supplied by the recorder (seat → id map) rather than read off the seat.
    public init(move: MoveResult, player: PlayerState, playerID: String?, participantID: Int?) {
        rowIndex = move.cell.row
        colIndex = move.cell.col
        playerId = playerID ?? ""
        currentScore = move.scoreAfter
        currentMultiplier = move.multiplierAfter
        multiplierIncrease = move.multiplierIncrease
        scoreIncrease = move.scoreIncrease
        newDiamondCount = move.newDiamonds.count
        newSquareCount = move.newSquares.count
        isCPU = player.isCPU
        cpuType = player.cpuLevel?.cpuType
        participantId = participantID
    }

    public var cell: Cell { Cell(row: rowIndex, col: colIndex) }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(rowIndex, forKey: .rowIndex)
        try c.encode(colIndex, forKey: .colIndex)
        try c.encode(playerId, forKey: .playerId)
        try c.encode(currentScore, forKey: .currentScore)
        try c.encode(currentMultiplier, forKey: .currentMultiplier)
        try c.encode(multiplierIncrease, forKey: .multiplierIncrease)
        try c.encode(scoreIncrease, forKey: .scoreIncrease)
        try c.encode(newDiamondCount, forKey: .newDiamondCount)
        try c.encode(newSquareCount, forKey: .newSquareCount)
        try c.encode(isCPU, forKey: .isCPU)
        try c.encode(cpuType, forKey: .cpuType)
        try c.encode(participantId, forKey: .participantId)
    }

    enum CodingKeys: String, CodingKey {
        case rowIndex = "row_index"
        case colIndex = "col_index"
        case playerId = "player_id"
        case currentScore = "current_score"
        case currentMultiplier = "current_multiplier"
        case multiplierIncrease = "multiplier_increase"
        case scoreIncrease = "score_increase"
        case newDiamondCount = "new_diamond_count"
        case newSquareCount = "new_square_count"
        case isCPU = "is_cpu"
        case cpuType = "cpu_type"
        case participantId = "participant_id"
    }
}

public struct GameTurnResponse: Codable, Sendable, Equatable {
    public let turnId: Int

    public init(turnId: Int) { self.turnId = turnId }

    enum CodingKeys: String, CodingKey {
        case turnId = "turn_id"
    }
}

// MARK: CPU

/// A board cell as the server reads it: only `id` (the seat number) matters.
public struct BoardCellDTO: Codable, Sendable, Equatable {
    public let id: Int
}

/// Existing shapes must be sent, or the server re-counts them as new when it evaluates moves.
public struct ShapeDTO: Codable, Sendable, Equatable {
    public let row: Int
    public let col: Int
    public let num: Int
    public let size: Int

    public init(_ shape: BoardShape) {
        row = shape.row
        col = shape.col
        num = shape.num
        size = shape.size
    }

    public init(row: Int, col: Int, num: Int, size: Int) {
        self.row = row
        self.col = col
        self.num = num
        self.size = size
    }

    public func boardShape(kind: ShapeKind, ownerID: Int) -> BoardShape {
        BoardShape(kind: kind, row: row, col: col, num: num, ownerID: ownerID)
    }
}

public struct CPUMovePlayer: Codable, Sendable, Equatable {
    public let id: Int
    public let name: String
    public let fillStyle: String
    public let playerId: String?
    public let participantId: Int?
    public let isCPU: Bool
    public let cpuType: String?
    public let currentScore: Int
    public let currentMultiplier: Int
    public let squares: [ShapeDTO]
    public let diamonds: [ShapeDTO]

    public init(_ player: PlayerState) {
        id = player.id
        name = player.name
        fillStyle = player.colorHex
        playerId = player.serverPlayerID
        participantId = player.participantID
        isCPU = player.isCPU
        cpuType = player.cpuLevel?.cpuType
        currentScore = player.score
        currentMultiplier = player.multiplier
        squares = player.squares.map(ShapeDTO.init)
        diamonds = player.diamonds.map(ShapeDTO.init)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(fillStyle, forKey: .fillStyle)
        try c.encode(playerId, forKey: .playerId)
        try c.encode(participantId, forKey: .participantId)
        try c.encode(isCPU, forKey: .isCPU)
        try c.encode(cpuType, forKey: .cpuType)
        try c.encode(currentScore, forKey: .currentScore)
        try c.encode(currentMultiplier, forKey: .currentMultiplier)
        try c.encode(squares, forKey: .squares)
        try c.encode(diamonds, forKey: .diamonds)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, fillStyle, playerId, participantId, isCPU, cpuType
        case currentScore, currentMultiplier, squares, diamonds
    }
}

public struct CPUMoveRequest: Codable, Sendable, Equatable {
    public let gameId: Int
    public let boardState: [[BoardCellDTO?]]
    public let currentPlayer: CPUMovePlayer
    public let gamePlayers: [CPUMovePlayer]
    public let cpuType: String

    public init(gameID: Int, game: Game) {
        gameId = gameID
        let board = game.board
        boardState = (0..<board.size).map { row in
            (0..<board.size).map { col in board[row, col].map(BoardCellDTO.init(id:)) }
        }
        currentPlayer = CPUMovePlayer(game.currentPlayer)
        gamePlayers = game.players.map(CPUMovePlayer.init)
        cpuType = game.currentPlayer.cpuLevel?.cpuType ?? CPULevel.random.cpuType
    }

    enum CodingKeys: String, CodingKey {
        case gameId = "game_id"
        case boardState = "board_state"
        case currentPlayer = "current_player"
        case gamePlayers = "game_players"
        case cpuType = "cpu_type"
    }
}

public struct CPUMoveResponse: Codable, Sendable, Equatable {
    public let row: Int
    public let col: Int

    public init(row: Int, col: Int) {
        self.row = row
        self.col = col
    }

    public var cell: Cell { Cell(row: row, col: col) }
}

// MARK: Auth (added for the server-integration pass)

public struct LoginResponse: Codable, Sendable, Equatable {
    public let message: String?
    /// Present once the server branch with bearer support is deployed; nil on older servers.
    public let accessToken: String?
    public let tokenType: String?

    public init(message: String?, accessToken: String?, tokenType: String? = "bearer") {
        self.message = message
        self.accessToken = accessToken
        self.tokenType = tokenType
    }

    enum CodingKeys: String, CodingKey {
        case message
        case accessToken = "access_token"
        case tokenType = "token_type"
    }
}

public struct RegisterResponse: Codable, Sendable, Equatable {
    public let message: String?
    public let playerId: String

    public init(message: String?, playerId: String) {
        self.message = message
        self.playerId = playerId
    }

    enum CodingKeys: String, CodingKey {
        case message
        case playerId = "player_id"
    }
}

public struct CheckAuthResponse: Codable, Sendable, Equatable {
    public let authenticated: Bool
    public let email: String?
    public let userId: String?
    public let appRole: String?

    enum CodingKeys: String, CodingKey {
        case authenticated, email
        case userId = "user_id"
        case appRole = "app_role"
    }
}

/// `GET /profile`. `createdAt` is kept as the server's string (no timezone), formatted by the UI.
public struct ProfileResponse: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let username: String
    public let email: String
    public let firstName: String
    public let lastName: String
    public let color: String
    public let createdAt: String
    public let appRole: String

    public init(id: String, username: String, email: String, firstName: String, lastName: String,
                color: String, createdAt: String, appRole: String = "standard") {
        self.id = id
        self.username = username
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.color = color
        self.createdAt = createdAt
        self.appRole = appRole
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        username = try c.decode(String.self, forKey: .username)
        email = try c.decode(String.self, forKey: .email)
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? "#0583D2"
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        appRole = try c.decodeIfPresent(String.self, forKey: .appRole) ?? "standard"
    }

    public var displayName: String {
        let full = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? username : full
    }

    enum CodingKeys: String, CodingKey {
        case id, username, email, color
        case firstName = "first_name"
        case lastName = "last_name"
        case createdAt = "created_at"
        case appRole = "app_role"
    }
}

/// `PATCH /profile`; only non-nil fields are sent.
public struct ProfileUpdateRequest: Codable, Sendable, Equatable {
    public let firstName: String?
    public let lastName: String?
    public let color: String?

    public init(firstName: String? = nil, lastName: String? = nil, color: String? = nil) {
        self.firstName = firstName
        self.lastName = lastName
        self.color = color
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(firstName, forKey: .firstName)
        try c.encodeIfPresent(lastName, forKey: .lastName)
        try c.encodeIfPresent(color, forKey: .color)
    }

    enum CodingKeys: String, CodingKey {
        case color
        case firstName = "first_name"
        case lastName = "last_name"
    }
}

public struct CreateGuestRequest: Codable, Sendable, Equatable {
    public let name: String
    public let color: String

    public init(name: String, color: String) {
        self.name = name
        self.color = color
    }
}

public struct CreateGuestResponse: Codable, Sendable, Equatable {
    public let message: String?
    public let playerId: String

    public init(message: String?, playerId: String) {
        self.message = message
        self.playerId = playerId
    }

    enum CodingKeys: String, CodingKey {
        case message
        case playerId = "player_id"
    }
}

public enum OAuthProvider: String, Sendable, CaseIterable, Codable {
    case google, github, apple
}

/// `client=ios` makes the server's callback redirect to `squareoff://auth?token=…`
/// instead of the web origin.
public enum OAuthClient: String, Sendable, Codable {
    case web, ios
}

public struct OAuthLoginResponse: Codable, Sendable, Equatable {
    public let url: URL
    public let state: String?

    public init(url: URL, state: String?) {
        self.url = url
        self.state = state
    }
}

/// `POST /apple/native`: the app's Sign in with Apple credential. `nonce` is the raw nonce whose
/// SHA-256 was sent to Apple; the server hashes it again to check the `id_token` claim.
public struct AppleNativeLoginRequest: Codable, Sendable, Equatable {
    public let identityToken: String
    public let nonce: String
    public let authorizationCode: String?
    public let fullName: String?

    public init(identityToken: String, nonce: String, authorizationCode: String? = nil, fullName: String? = nil) {
        self.identityToken = identityToken
        self.nonce = nonce
        self.authorizationCode = authorizationCode
        self.fullName = fullName
    }

    enum CodingKeys: String, CodingKey {
        case nonce
        case identityToken = "identity_token"
        case authorizationCode = "authorization_code"
        case fullName = "full_name"
    }
}

// MARK: Game end / players

/// One entry of `PUT /end` → `scores`. camelCase, like the web's `ScoreEntry`.
public struct ScoreEntry: Codable, Sendable, Equatable {
    public let playerId: String
    public let score: Int

    public init(playerId: String, score: Int) {
        self.playerId = playerId
        self.score = score
    }
}

public struct GameEndRequest: Codable, Sendable, Equatable {
    public let gameId: Int
    /// User/guest UUID, CPU definition id, or "" for a draw.
    public let winnerId: String
    public let scores: [ScoreEntry]

    public init(gameId: Int, winnerId: String, scores: [ScoreEntry]) {
        self.gameId = gameId
        self.winnerId = winnerId
        self.scores = scores
    }

    enum CodingKeys: String, CodingKey {
        case scores
        case gameId = "game_id"
        case winnerId = "winner_id"
    }
}

struct UpdatePlayersRequest: Encodable {
    let gameId: Int
    let players: [PlayerPayload]

    enum CodingKeys: String, CodingKey {
        case players
        case gameId = "game_id"
    }
}

// MARK: Stats

public struct PlayerStatsView: Codable, Sendable, Equatable {
    public let playerId: String
    public let username: String
    public let email: String
    public let firstName: String
    public let lastName: String
    public let color: String
    public let createdAt: String
    public let totalGamesPlayed: Int
    public let gamesWon: Int
    public let gamesLost: Int
    public let winPercentage: Double
    public let avgGameDuration: Double
    public let highestScore: Int
    public let avgFinalScore: Double
    public let localGamesPlayed: Int

    public init(playerId: String, username: String, email: String, firstName: String, lastName: String,
                color: String, createdAt: String, totalGamesPlayed: Int, gamesWon: Int, gamesLost: Int,
                winPercentage: Double, avgGameDuration: Double, highestScore: Int, avgFinalScore: Double,
                localGamesPlayed: Int) {
        self.playerId = playerId
        self.username = username
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.color = color
        self.createdAt = createdAt
        self.totalGamesPlayed = totalGamesPlayed
        self.gamesWon = gamesWon
        self.gamesLost = gamesLost
        self.winPercentage = winPercentage
        self.avgGameDuration = avgGameDuration
        self.highestScore = highestScore
        self.avgFinalScore = avgFinalScore
        self.localGamesPlayed = localGamesPlayed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playerId = try c.decode(String.self, forKey: .playerId)
        username = try c.decode(String.self, forKey: .username)
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? "#0583D2"
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        totalGamesPlayed = try c.decodeIfPresent(Int.self, forKey: .totalGamesPlayed) ?? 0
        gamesWon = try c.decodeIfPresent(Int.self, forKey: .gamesWon) ?? 0
        gamesLost = try c.decodeIfPresent(Int.self, forKey: .gamesLost) ?? 0
        winPercentage = try c.decodeIfPresent(Double.self, forKey: .winPercentage) ?? 0
        avgGameDuration = try c.decodeIfPresent(Double.self, forKey: .avgGameDuration) ?? 0
        highestScore = try c.decodeIfPresent(Int.self, forKey: .highestScore) ?? 0
        avgFinalScore = try c.decodeIfPresent(Double.self, forKey: .avgFinalScore) ?? 0
        localGamesPlayed = try c.decodeIfPresent(Int.self, forKey: .localGamesPlayed) ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case username, email, color
        case playerId = "player_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case createdAt = "created_at"
        case totalGamesPlayed = "total_games_played"
        case gamesWon = "games_won"
        case gamesLost = "games_lost"
        case winPercentage = "win_percentage"
        case avgGameDuration = "avg_game_duration"
        case highestScore = "highest_score"
        case avgFinalScore = "avg_final_score"
        case localGamesPlayed = "local_games_played"
    }
}

public struct PlayerStatsCPUView: Codable, Sendable, Equatable, Identifiable {
    public let playerId: String
    public let username: String
    public let cpuType: String
    public let totalGamesPlayed: Int
    public let gamesWon: Int
    public let gamesLost: Int
    public let winPercentage: Double
    public let avgGameDuration: Double
    public let highestScore: Int
    public let avgFinalScore: Double
    public let localGamesPlayed: Int

    public var id: String { cpuType }

    public init(playerId: String, username: String, cpuType: String, totalGamesPlayed: Int, gamesWon: Int,
                gamesLost: Int, winPercentage: Double, avgGameDuration: Double, highestScore: Int,
                avgFinalScore: Double, localGamesPlayed: Int) {
        self.playerId = playerId
        self.username = username
        self.cpuType = cpuType
        self.totalGamesPlayed = totalGamesPlayed
        self.gamesWon = gamesWon
        self.gamesLost = gamesLost
        self.winPercentage = winPercentage
        self.avgGameDuration = avgGameDuration
        self.highestScore = highestScore
        self.avgFinalScore = avgFinalScore
        self.localGamesPlayed = localGamesPlayed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playerId = try c.decode(String.self, forKey: .playerId)
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        cpuType = try c.decodeIfPresent(String.self, forKey: .cpuType) ?? ""
        totalGamesPlayed = try c.decodeIfPresent(Int.self, forKey: .totalGamesPlayed) ?? 0
        gamesWon = try c.decodeIfPresent(Int.self, forKey: .gamesWon) ?? 0
        gamesLost = try c.decodeIfPresent(Int.self, forKey: .gamesLost) ?? 0
        winPercentage = try c.decodeIfPresent(Double.self, forKey: .winPercentage) ?? 0
        avgGameDuration = try c.decodeIfPresent(Double.self, forKey: .avgGameDuration) ?? 0
        highestScore = try c.decodeIfPresent(Int.self, forKey: .highestScore) ?? 0
        avgFinalScore = try c.decodeIfPresent(Double.self, forKey: .avgFinalScore) ?? 0
        localGamesPlayed = try c.decodeIfPresent(Int.self, forKey: .localGamesPlayed) ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case username
        case playerId = "player_id"
        case cpuType = "cpu_type"
        case totalGamesPlayed = "total_games_played"
        case gamesWon = "games_won"
        case gamesLost = "games_lost"
        case winPercentage = "win_percentage"
        case avgGameDuration = "avg_game_duration"
        case highestScore = "highest_score"
        case avgFinalScore = "avg_final_score"
        case localGamesPlayed = "local_games_played"
    }
}

public struct ProfileStatsFilters: Codable, Sendable, Equatable {
    public let boardSizes: [Int]
    public let timers: [Int]
    public let cpuTypes: [String]

    public init(boardSizes: [Int], timers: [Int], cpuTypes: [String]) {
        self.boardSizes = boardSizes
        self.timers = timers
        self.cpuTypes = cpuTypes
    }

    enum CodingKeys: String, CodingKey {
        case timers
        case boardSizes = "board_sizes"
        case cpuTypes = "cpu_types"
    }
}

public struct RecentGameRow: Codable, Sendable, Equatable, Identifiable {
    public let gameId: Int
    public let gameType: String
    public let opponentLabel: String
    public let myScore: Int
    /// "W", "L" or "T".
    public let result: String

    public var id: Int { gameId }

    public init(gameId: Int, gameType: String, opponentLabel: String, myScore: Int, result: String) {
        self.gameId = gameId
        self.gameType = gameType
        self.opponentLabel = opponentLabel
        self.myScore = myScore
        self.result = result
    }

    enum CodingKeys: String, CodingKey {
        case result
        case gameId = "game_id"
        case gameType = "game_type"
        case opponentLabel = "opponent_label"
        case myScore = "my_score"
    }
}

public struct RecentGamesPage: Codable, Sendable, Equatable {
    public let games: [RecentGameRow]
    public let total: Int

    public init(games: [RecentGameRow], total: Int) {
        self.games = games
        self.total = total
    }
}

// MARK: Replay

public struct ReplayParticipant: Codable, Sendable, Equatable, Identifiable {
    public let participantId: Int
    public let boardSlotId: Int
    public let displayName: String
    public let color: String
    /// "user", "guest" or "cpu".
    public let participantType: String
    public let cpuType: String?

    public var id: Int { participantId }

    public init(participantId: Int, boardSlotId: Int, displayName: String, color: String, participantType: String, cpuType: String?) {
        self.participantId = participantId
        self.boardSlotId = boardSlotId
        self.displayName = displayName
        self.color = color
        self.participantType = participantType
        self.cpuType = cpuType
    }

    enum CodingKeys: String, CodingKey {
        case color
        case participantId = "participant_id"
        case boardSlotId = "board_slot_id"
        case displayName = "display_name"
        case participantType = "participant_type"
        case cpuType = "cpu_type"
    }
}

public struct ReplayTurn: Codable, Sendable, Equatable {
    public let turnNumber: Int
    public let boardSlotId: Int
    public let rowIndex: Int
    public let colIndex: Int

    public var cell: Cell { Cell(row: rowIndex, col: colIndex) }

    public init(turnNumber: Int, boardSlotId: Int, rowIndex: Int, colIndex: Int) {
        self.turnNumber = turnNumber
        self.boardSlotId = boardSlotId
        self.rowIndex = rowIndex
        self.colIndex = colIndex
    }

    enum CodingKeys: String, CodingKey {
        case turnNumber = "turn_number"
        case boardSlotId = "board_slot_id"
        case rowIndex = "row_index"
        case colIndex = "col_index"
    }
}

public struct GameReplayPayload: Codable, Sendable, Equatable {
    public let gameId: Int
    public let boardSize: Int
    public let timer: Int
    public let gameType: String
    public let participants: [ReplayParticipant]
    public let turns: [ReplayTurn]

    public init(gameId: Int, boardSize: Int, timer: Int, gameType: String, participants: [ReplayParticipant], turns: [ReplayTurn]) {
        self.gameId = gameId
        self.boardSize = boardSize
        self.timer = timer
        self.gameType = gameType
        self.participants = participants
        self.turns = turns
    }

    enum CodingKeys: String, CodingKey {
        case timer, participants, turns
        case gameId = "game_id"
        case boardSize = "board_size"
        case gameType = "game_type"
    }
}
