import Foundation

// The admin console's wire shapes (`hero-client/src/services/adminAPI.ts`, served by
// `server/src/routes/admin*.py`). Keys are snake_case except where the server kept camelCase
// (`isCPU` in the live snapshot). Enums decode unknown server values as `.unknown` so a new
// value never breaks a screen; naive-UTC timestamps (`games.*`, `users.created_at`) and
// offset timestamps (audit, feedback) both arrive as strings and are parsed by the app.

// MARK: - Shared

public enum AppRole: String, Codable, Sendable, Equatable, CaseIterable {
    case standard, superadmin
}

public enum SortDir: String, Codable, Sendable, Equatable {
    case asc, desc
}

public enum ParticipantType: String, Codable, Sendable, Equatable {
    case user, guest, cpu
}

public enum AuthProvider: String, Codable, Sendable, Equatable, CaseIterable {
    case password, google, github, apple
}

/// `{total, items}` from every paged admin list.
public struct Paged<Item: Codable & Sendable & Equatable>: Codable, Sendable, Equatable {
    public let total: Int
    public let items: [Item]

    public init(total: Int, items: [Item]) {
        self.total = total
        self.items = items
    }
}

/// `{id, username, email}` of an admin, a target or a sender.
public struct AdminActor: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let username: String?
    public let email: String?

    public init(id: String, username: String?, email: String?) {
        self.id = id
        self.username = username
        self.email = email
    }

    public var label: String { username ?? email ?? String(id.prefix(8)) }
}

/// Arbitrary jsonb (`games.scores`, `audit.detail`), kept as a tree for display.
public indirect enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value") }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// Pretty-printed, keys sorted, for the audit detail popover.
    public var prettyPrinted: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    /// The string behind `.string`, a whole number behind `.number`, or nil.
    public var stringValue: String? {
        switch self {
        case .string(let value): value
        case .number(let value): value == value.rounded() ? String(Int(value)) : String(value)
        case .bool(let value): value ? "true" : "false"
        default: nil
        }
    }
}

/// Decodes an unknown raw value as `.unknown` instead of failing the whole response.
public protocol LenientEnum: RawRepresentable, Codable where RawValue == String {
    static var unknown: Self { get }
}

extension LenientEnum {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .unknown
    }
}

// MARK: - Health

public struct AdminHealth: Codable, Sendable, Equatable {
    public struct Database: Codable, Sendable, Equatable {
        public struct Pool: Codable, Sendable, Equatable {
            public let min: Int
            public let max: Int
            public let inUse: Int
            public let idle: Int

            enum CodingKeys: String, CodingKey { case min, max, inUse = "in_use", idle }
        }

        public let ok: Bool
        public let latencyMs: Double?
        public let pool: Pool?
        public let error: String?

        enum CodingKeys: String, CodingKey { case ok, latencyMs = "latency_ms", pool, error }
    }

    public struct Model: Codable, Sendable, Equatable {
        public struct Move: Codable, Sendable, Equatable {
            public let row: Int
            public let col: Int
        }

        public let ok: Bool
        public let latencyMs: Double?
        public let cached: Bool
        public let checkedAt: String?
        public let move: Move?
        public let error: String?

        enum CodingKeys: String, CodingKey { case ok, latencyMs = "latency_ms", cached, checkedAt = "checked_at", move, error }
    }

    public struct Mail: Codable, Sendable, Equatable {
        public let configured: Bool
        public let server: String?
    }

    /// The Rust engine behind levels 7–8 (2026-10-29 server); `model` is the level-8 neural
    /// network probe since then. Absent on older servers.
    public struct Engine: Codable, Sendable, Equatable {
        public let ok: Bool
        public let latencyMs: Double?
        public let cached: Bool
        public let checkedAt: String?
        public let version: String?
        public let move: Model.Move?
        public let error: String?

        public init(ok: Bool, latencyMs: Double?, cached: Bool, checkedAt: String?, version: String?, move: Model.Move?, error: String?) {
            self.ok = ok
            self.latencyMs = latencyMs
            self.cached = cached
            self.checkedAt = checkedAt
            self.version = version
            self.move = move
            self.error = error
        }

        enum CodingKeys: String, CodingKey { case ok, latencyMs = "latency_ms", cached, checkedAt = "checked_at", version, move, error }
    }

    public struct App: Codable, Sendable, Equatable {
        public let version: String
        public let buildSha: String?
        public let env: String
        public let startedAt: String
        public let uptimeS: Double
        public let python: String?
        public let fastapi: String?
        public let rateLimitStorage: String?

        enum CodingKeys: String, CodingKey {
            case version, buildSha = "build_sha", env, startedAt = "started_at", uptimeS = "uptime_s", python, fastapi
            case rateLimitStorage = "rate_limit_storage"
        }
    }

    public let db: Database
    public let model: Model
    public let mail: Mail
    public let app: App
    public let engine: Engine?

    public init(db: Database, model: Model, mail: Mail, app: App, engine: Engine? = nil) {
        self.db = db
        self.model = model
        self.mail = mail
        self.app = app
        self.engine = engine
    }
}

// MARK: - Live

public enum AdminLivePhase: String, LenientEnum, Sendable, Equatable {
    case lobby, playing, gameOver = "game_over", hostAway = "host_away", unknown
}

public struct AdminLivePlayer: Codable, Sendable, Equatable, Identifiable {
    public let slot: Int
    public let name: String
    public let isCPU: Bool
    public let playerId: String?
    public let score: Int
    public let connected: Bool
    public let awaySeconds: Double?

    public var id: Int { slot }

    enum CodingKeys: String, CodingKey {
        case slot, name, isCPU, playerId = "player_id", score, connected, awaySeconds = "away_seconds"
    }
}

public struct AdminLiveRoom: Codable, Sendable, Equatable, Identifiable {
    public let roomCode: Int
    public let phase: AdminLivePhase
    public let boardSize: Int
    public let timer: Int
    public let gameId: Int?
    public let matchInProgress: Bool
    public let hostConnected: Bool
    public let hostAwaySeconds: Double?
    public let players: [AdminLivePlayer]
    public let guestConnections: Int
    public let spectatorCount: Int
    public let turnIndex: Int?
    public let movesPlayed: Int
    public let gameOver: Bool

    public var id: Int { roomCode }

    enum CodingKeys: String, CodingKey {
        case roomCode = "room_code", phase, boardSize = "board_size", timer, gameId = "game_id"
        case matchInProgress = "match_in_progress", hostConnected = "host_connected", hostAwaySeconds = "host_away_seconds"
        case players, guestConnections = "guest_connections", spectatorCount = "spectator_count", turnIndex = "turn_index"
        case movesPlayed = "moves_played", gameOver = "game_over"
    }
}

public struct AdminLiveOpenRoom: Codable, Sendable, Equatable, Identifiable {
    public let roomCode: Int
    public let boardSize: Int
    public let timer: Int
    public let slotsFilled: Int
    public let slotsMax: Int
    public let listed: Bool
    public let hostLabel: String
    public let hostKey: String
    public let gameId: Int?
    public let createdAt: Double
    public let ageS: Double
    public let heartbeatAgeS: Double

    public var id: Int { roomCode }

    enum CodingKeys: String, CodingKey {
        case roomCode = "room_code", boardSize = "board_size", timer, slotsFilled = "slots_filled", slotsMax = "slots_max"
        case listed, hostLabel = "host_label", hostKey = "host_key", gameId = "game_id", createdAt = "created_at"
        case ageS = "age_s", heartbeatAgeS = "heartbeat_age_s"
    }
}

public struct AdminLiveQueueItem: Codable, Sendable, Equatable, Identifiable {
    public let ticketId: String
    public let boardSize: Int
    public let timer: Int
    public let waitS: Double
    public let assignedRoomCode: Int?
    public let shouldCreateRoom: Bool
    public let acknowledged: Bool

    public var id: String { ticketId }

    enum CodingKeys: String, CodingKey {
        case ticketId = "ticket_id", boardSize = "board_size", timer, waitS = "wait_s"
        case assignedRoomCode = "assigned_room_code", shouldCreateRoom = "should_create_room", acknowledged
    }
}

public struct AdminLiveSnapshot: Codable, Sendable, Equatable {
    public struct Sockets: Codable, Sendable, Equatable {
        public let connections: Int
        public let inRooms: Int

        enum CodingKeys: String, CodingKey { case connections, inRooms = "in_rooms" }
    }

    public struct Queue: Codable, Sendable, Equatable {
        public let tickets: Int
        public let oldestWaitS: Double?
        public let pairsPending: Int
        public let items: [AdminLiveQueueItem]

        enum CodingKeys: String, CodingKey {
            case tickets, oldestWaitS = "oldest_wait_s", pairsPending = "pairs_pending", items
        }
    }

    public let generatedAt: String
    public let websocket: Sockets
    public let rooms: [AdminLiveRoom]
    public let openRooms: [AdminLiveOpenRoom]
    public let matchQueue: Queue

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at", websocket, rooms, openRooms = "open_rooms", matchQueue = "match_queue"
    }
}

// MARK: - Timeseries

public struct AdminTimeseriesPoint: Codable, Sendable, Equatable, Identifiable {
    public struct Started: Codable, Sendable, Equatable {
        public let local: Int
        public let online: Int
        public let cpu: Int

        public var total: Int { local + online + cpu }
    }

    /// Local date `YYYY-MM-DD` in the requested time zone.
    public let date: String
    public let gamesStarted: Started
    public let gamesCompleted: Int
    public let newUsers: Int
    public let newGuestSessions: Int

    public var id: String { date }

    enum CodingKeys: String, CodingKey {
        case date, gamesStarted = "games_started", gamesCompleted = "games_completed", newUsers = "new_users"
        case newGuestSessions = "new_guest_sessions"
    }
}

public struct AdminTimeseriesTotals: Codable, Sendable, Equatable {
    public struct ProviderCount: Codable, Sendable, Equatable, Identifiable {
        public let provider: String
        public let count: Int
        public var id: String { provider }
    }

    public struct ParticipantSplit: Codable, Sendable, Equatable {
        public let user: Int
        public let guest: Int
        public let cpu: Int
    }

    public let gamesStarted: Int
    public let gamesCompleted: Int
    public let completionRate: Double?
    public let medianDurationMin: Double?
    public let medianDurationMinOnline: Double?
    public let dau: Int
    public let wau: Int
    public let mau: Int
    public let registeredUsers: Int
    public let providerMix: [ProviderCount]
    public let guestVsRegisteredParticipants: ParticipantSplit

    enum CodingKeys: String, CodingKey {
        case gamesStarted = "games_started", gamesCompleted = "games_completed", completionRate = "completion_rate"
        case medianDurationMin = "median_duration_min", medianDurationMinOnline = "median_duration_min_online"
        case dau, wau, mau, registeredUsers = "registered_users", providerMix = "provider_mix"
        case guestVsRegisteredParticipants = "guest_vs_registered_participants"
    }
}

public struct AdminTimeseries: Codable, Sendable, Equatable {
    public let days: Int
    public let tz: String
    public let from: String
    public let to: String
    public let series: [AdminTimeseriesPoint]
    public let totals: AdminTimeseriesTotals
}

// MARK: - Users

public struct AdminUserRow: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let email: String
    public let username: String
    public let firstName: String
    public let lastName: String
    public let appRole: AppRole
    public let isActive: Bool
    public let createdAt: String?
    public let lastLoginAt: String?
    public let gamesPlayed: Int
    public let sessionVersion: Int
    public let oauthProvider: String?
    /// When the address was verified (sign-up link, OAuth, or an admin); nil = password sign-in blocked.
    public let emailVerifiedAt: String?
    /// The server's bot heuristic: unverified password-only account, random-case username, no games.
    public let isSuspect: Bool

    public var isEmailVerified: Bool { emailVerifiedAt != nil }

    enum CodingKeys: String, CodingKey {
        case id, email, username, firstName = "first_name", lastName = "last_name", appRole = "app_role"
        case isActive = "is_active", createdAt = "created_at", lastLoginAt = "last_login_at", gamesPlayed = "games_played"
        case sessionVersion = "session_version", oauthProvider = "oauth_provider"
        case emailVerifiedAt = "email_verified_at", isSuspect = "is_suspect"
    }
}

extension AdminUserRow {
    /// Older servers (and fixtures) have no verification fields; decode them as "verified, not suspect".
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        email = try c.decode(String.self, forKey: .email)
        username = try c.decode(String.self, forKey: .username)
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        appRole = try c.decode(AppRole.self, forKey: .appRole)
        isActive = try c.decode(Bool.self, forKey: .isActive)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        lastLoginAt = try c.decodeIfPresent(String.self, forKey: .lastLoginAt)
        gamesPlayed = try c.decodeIfPresent(Int.self, forKey: .gamesPlayed) ?? 0
        sessionVersion = try c.decodeIfPresent(Int.self, forKey: .sessionVersion) ?? 0
        oauthProvider = try c.decodeIfPresent(String.self, forKey: .oauthProvider)
        emailVerifiedAt = try c.decodeIfPresent(String.self, forKey: .emailVerifiedAt)
        isSuspect = try c.decodeIfPresent(Bool.self, forKey: .isSuspect) ?? false
    }
}

/// `POST /admin/users/bulk-deactivate`: exactly one of `user_ids` (1–500) or `filter: "suspect"`.
public struct BulkDeactivateRequest: Codable, Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        case ids([String])
        /// Every active account the server's suspected-bot filter matches, up to 500 per call.
        case suspects
    }

    public var source: Source
    /// Free text kept in the audit rows (≤ 200 characters).
    public var reason: String?

    public init(source: Source, reason: String? = nil) {
        self.source = source
        self.reason = reason
    }

    public static func ids(_ ids: [String], reason: String? = nil) -> BulkDeactivateRequest { .init(source: .ids(ids), reason: reason) }
    public static func suspects(reason: String? = nil) -> BulkDeactivateRequest { .init(source: .suspects, reason: reason) }

    enum CodingKeys: String, CodingKey { case userIds = "user_ids", filter, reason }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch source {
        case .ids(let ids): try c.encode(ids, forKey: .userIds)
        case .suspects: try c.encode("suspect", forKey: .filter)
        }
        try c.encodeIfPresent(reason, forKey: .reason)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let ids = try c.decodeIfPresent([String].self, forKey: .userIds) {
            source = .ids(ids)
        } else if try c.decodeIfPresent(String.self, forKey: .filter) == "suspect" {
            source = .suspects
        } else {
            throw DecodingError.dataCorruptedError(forKey: .filter, in: c, debugDescription: "user_ids or filter=suspect expected")
        }
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
    }
}

public struct AdminBulkDeactivateResult: Codable, Sendable, Equatable {
    public let deactivated: Int
    /// Already inactive, superadmins, CPUs and the caller are skipped.
    public let skipped: Int
    /// Shared by the audit rows of one call; nil when nothing was deactivated.
    public let batchId: String?

    public init(deactivated: Int, skipped: Int, batchId: String?) {
        self.deactivated = deactivated
        self.skipped = skipped
        self.batchId = batchId
    }

    enum CodingKeys: String, CodingKey { case deactivated, skipped, batchId = "batch_id" }
}

public struct AdminUserDetail: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let email: String
    public let username: String
    public let firstName: String
    public let lastName: String
    public let color: String
    public let appRole: AppRole
    public let isActive: Bool
    public let createdAt: String?
    public let registered: Bool
    public let isCpu: Bool
    public let lastLoginAt: String?
    public let sessionVersion: Int
    public let updatedAt: String?
    public let oauthProvider: String?
    public let profilePictureUrl: String?
    /// nil = the address is unverified and password sign-in is blocked (absent on older servers).
    public let emailVerifiedAt: String?

    public init(id: String, email: String, username: String, firstName: String, lastName: String, color: String, appRole: AppRole,
                isActive: Bool, createdAt: String?, registered: Bool, isCpu: Bool, lastLoginAt: String?, sessionVersion: Int,
                updatedAt: String?, oauthProvider: String?, profilePictureUrl: String?, emailVerifiedAt: String? = nil) {
        self.id = id
        self.email = email
        self.username = username
        self.firstName = firstName
        self.lastName = lastName
        self.color = color
        self.appRole = appRole
        self.isActive = isActive
        self.createdAt = createdAt
        self.registered = registered
        self.isCpu = isCpu
        self.lastLoginAt = lastLoginAt
        self.sessionVersion = sessionVersion
        self.updatedAt = updatedAt
        self.oauthProvider = oauthProvider
        self.profilePictureUrl = profilePictureUrl
        self.emailVerifiedAt = emailVerifiedAt
    }

    /// A copy with some fields changed (the mock's writes); `emailVerifiedAt: .some(nil)` clears it.
    public func updating(username: String? = nil, firstName: String? = nil, lastName: String? = nil, color: String? = nil,
                         appRole: AppRole? = nil, isActive: Bool? = nil, sessionVersion: Int? = nil, updatedAt: String? = nil,
                         emailVerifiedAt: String?? = nil) -> AdminUserDetail {
        AdminUserDetail(id: id, email: email, username: username ?? self.username, firstName: firstName ?? self.firstName,
                        lastName: lastName ?? self.lastName, color: color ?? self.color, appRole: appRole ?? self.appRole,
                        isActive: isActive ?? self.isActive, createdAt: createdAt, registered: registered, isCpu: isCpu,
                        lastLoginAt: lastLoginAt, sessionVersion: sessionVersion ?? self.sessionVersion, updatedAt: updatedAt ?? self.updatedAt,
                        oauthProvider: oauthProvider, profilePictureUrl: profilePictureUrl,
                        emailVerifiedAt: emailVerifiedAt.map { $0 } ?? self.emailVerifiedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id, email, username, firstName = "first_name", lastName = "last_name", color, appRole = "app_role"
        case isActive = "is_active", createdAt = "created_at", registered, isCpu = "is_cpu", lastLoginAt = "last_login_at"
        case sessionVersion = "session_version", updatedAt = "updated_at", oauthProvider = "oauth_provider"
        case profilePictureUrl = "profile_picture_url", emailVerifiedAt = "email_verified_at"
    }

    public var displayName: String {
        let name = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? username : name
    }
}

/// `PATCH /admin/users/{id}`; only the fields that are set are sent.
public struct AdminUserPatch: Codable, Sendable, Equatable {
    public var appRole: AppRole?
    public var isActive: Bool?
    public var firstName: String?
    public var lastName: String?
    public var username: String?
    public var color: String?
    /// `true` stamps `email_verified_at` (kept if already set), `false` clears it.
    public var emailVerified: Bool?

    public init(appRole: AppRole? = nil, isActive: Bool? = nil, firstName: String? = nil, lastName: String? = nil,
                username: String? = nil, color: String? = nil, emailVerified: Bool? = nil) {
        self.appRole = appRole
        self.isActive = isActive
        self.firstName = firstName
        self.lastName = lastName
        self.username = username
        self.color = color
        self.emailVerified = emailVerified
    }

    enum CodingKeys: String, CodingKey {
        case appRole = "app_role", isActive = "is_active", firstName = "first_name", lastName = "last_name", username, color
        case emailVerified = "email_verified"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(appRole, forKey: .appRole)
        try c.encodeIfPresent(isActive, forKey: .isActive)
        try c.encodeIfPresent(firstName, forKey: .firstName)
        try c.encodeIfPresent(lastName, forKey: .lastName)
        try c.encodeIfPresent(username, forKey: .username)
        try c.encodeIfPresent(color, forKey: .color)
        try c.encodeIfPresent(emailVerified, forKey: .emailVerified)
    }

    public var isEmpty: Bool {
        appRole == nil && isActive == nil && firstName == nil && lastName == nil && username == nil && color == nil && emailVerified == nil
    }
}

public struct AdminUserIdentity: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let provider: String
    public let providerSub: String
    public let providerEmail: String?
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, provider, providerSub = "provider_sub", providerEmail = "provider_email", createdAt = "created_at"
    }
}

public struct AdminUserEntitlement: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let entitlementType: String
    public let entitlementValue: String?
    public let grantedAt: String
    public let expiresAt: String?
    public let source: String

    enum CodingKeys: String, CodingKey {
        case id, entitlementType = "entitlement_type", entitlementValue = "entitlement_value", grantedAt = "granted_at"
        case expiresAt = "expires_at", source
    }
}

public struct AdminUserOverview: Codable, Sendable, Equatable {
    public let user: AdminUserDetail
    public let stats: PlayerStatsView?
    public let gamesPlayed: Int
    public let lastPlayedAt: String?
    public let gamesAbandoned: Int
    public let identities: [AdminUserIdentity]
    public let entitlements: [AdminUserEntitlement]
    public let auditCount: Int
    public let feedbackCount: Int

    enum CodingKeys: String, CodingKey {
        case user, stats, gamesPlayed = "games_played", lastPlayedAt = "last_played_at", gamesAbandoned = "games_abandoned"
        case identities, entitlements, auditCount = "audit_count", feedbackCount = "feedback_count"
    }
}

public enum AdminUserGameResult: String, LenientEnum, Sendable, Equatable {
    case win = "W", loss = "L", tie = "T", unfinished, unknown
}

public struct AdminUserGameRow: Codable, Sendable, Equatable, Identifiable {
    public let gameId: Int
    public let gameType: String
    public let startTime: String?
    public let endTime: String?
    public let boardSize: Int
    public let timer: Int
    public let myScore: Int?
    public let result: AdminUserGameResult
    public let opponentLabel: String
    public let replayAvailable: Bool
    public let replayUrl: String?

    public var id: Int { gameId }

    enum CodingKeys: String, CodingKey {
        case gameId = "game_id", gameType = "game_type", startTime = "start_time", endTime = "end_time"
        case boardSize = "board_size", timer, myScore = "my_score", result, opponentLabel = "opponent_label"
        case replayAvailable = "replay_available", replayUrl = "replay_url"
    }
}

public struct AdminForceLogoutResult: Codable, Sendable, Equatable {
    public let message: String
    public let sessionVersion: Int

    enum CodingKeys: String, CodingKey { case message, sessionVersion = "session_version" }
}

// MARK: - Games

public struct AdminGameParticipant: Codable, Sendable, Equatable, Identifiable {
    public let participantId: Int
    public let participantType: ParticipantType
    public let displayName: String
    public let color: String
    public let userId: String?
    public let username: String?
    public let guestId: String?
    public let cpuDefinitionId: Int?
    public let cpuType: String?
    public let finalScore: Int?
    public let participantOrder: Int
    public let isWinner: Bool

    public var id: Int { participantId }

    enum CodingKeys: String, CodingKey {
        case participantId = "participant_id", participantType = "participant_type", displayName = "display_name", color
        case userId = "user_id", username, guestId = "guest_id", cpuDefinitionId = "cpu_definition_id", cpuType = "cpu_type"
        case finalScore = "final_score", participantOrder = "participant_order", isWinner = "is_winner"
    }
}

public struct AdminGameRow: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let type: String
    public let startTime: String?
    public let endTime: String?
    public let boardSize: Int
    public let timer: Int
    public let winnerId: String?
    public let winnerParticipantId: Int?
    public let winnerDisplay: String?
    public let scores: JSONValue?
    public let isCpu: Bool
    public let cpuType: String?
    public let participantCount: Int
    public let durationSec: Int?
    public let winnerType: ParticipantType?
    public let participants: [AdminGameParticipant]

    enum CodingKeys: String, CodingKey {
        case id, type, startTime = "start_time", endTime = "end_time", boardSize = "board_size", timer
        case winnerId = "winner_id", winnerParticipantId = "winner_participant_id", winnerDisplay = "winner_display", scores
        case isCpu = "is_cpu", cpuType = "cpu_type", participantCount = "participant_count", durationSec = "duration_sec"
        case winnerType = "winner_type", participants
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        type = try c.decode(String.self, forKey: .type)
        startTime = try c.decodeIfPresent(String.self, forKey: .startTime)
        endTime = try c.decodeIfPresent(String.self, forKey: .endTime)
        boardSize = try c.decode(Int.self, forKey: .boardSize)
        timer = try c.decodeIfPresent(Int.self, forKey: .timer) ?? 0
        winnerId = try c.decodeIfPresent(String.self, forKey: .winnerId)
        winnerParticipantId = try c.decodeIfPresent(Int.self, forKey: .winnerParticipantId)
        winnerDisplay = try c.decodeIfPresent(String.self, forKey: .winnerDisplay)
        scores = try c.decodeIfPresent(JSONValue.self, forKey: .scores)
        isCpu = try c.decodeIfPresent(Bool.self, forKey: .isCpu) ?? false
        cpuType = try c.decodeIfPresent(String.self, forKey: .cpuType)
        participantCount = try c.decodeIfPresent(Int.self, forKey: .participantCount) ?? 0
        durationSec = try c.decodeIfPresent(Int.self, forKey: .durationSec)
        winnerType = try c.decodeIfPresent(ParticipantType.self, forKey: .winnerType)
        participants = try c.decodeIfPresent([AdminGameParticipant].self, forKey: .participants) ?? []
    }

    public init(id: Int, type: String, startTime: String?, endTime: String?, boardSize: Int, timer: Int, winnerId: String?,
                winnerParticipantId: Int?, winnerDisplay: String?, scores: JSONValue?, isCpu: Bool, cpuType: String?,
                participantCount: Int, durationSec: Int?, winnerType: ParticipantType?, participants: [AdminGameParticipant]) {
        self.id = id
        self.type = type
        self.startTime = startTime
        self.endTime = endTime
        self.boardSize = boardSize
        self.timer = timer
        self.winnerId = winnerId
        self.winnerParticipantId = winnerParticipantId
        self.winnerDisplay = winnerDisplay
        self.scores = scores
        self.isCpu = isCpu
        self.cpuType = cpuType
        self.participantCount = participantCount
        self.durationSec = durationSec
        self.winnerType = winnerType
        self.participants = participants
    }
}

public enum AdminGameWinnerFilter: String, Codable, Sendable, Equatable, CaseIterable {
    case user, cpu, guest, draw, unfinished
}

public enum AdminGameSort: String, Codable, Sendable, Equatable, CaseIterable {
    case startTime = "start_time", endTime = "end_time", duration
}

// MARK: - Audit

public enum AdminAuditAction: String, LenientEnum, Sendable, Equatable, CaseIterable {
    case userPatch = "user_patch", resetPassword = "reset_password", forceLogout = "force_logout"
    case cpuCreate = "cpu_create", cpuPatch = "cpu_patch", cpuDelete = "cpu_delete", feedbackPatch = "feedback_patch"
    case passwordResetSelf = "password_reset_self", accountDeleteSelf = "account_delete_self"
    /// One row per account of a `POST /admin/users/bulk-deactivate` call; rows share `detail.batch_id`.
    case bulkDeactivate = "bulk_deactivate"
    case unknown

    public static var allCases: [AdminAuditAction] {
        [.userPatch, .resetPassword, .forceLogout, .cpuCreate, .cpuPatch, .cpuDelete, .feedbackPatch, .bulkDeactivate, .passwordResetSelf, .accountDeleteSelf]
    }
}

public struct AdminAuditRow: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let createdAt: String
    public let action: AdminAuditAction
    public let admin: AdminActor
    public let target: AdminActor?
    public let detail: JSONValue?

    enum CodingKeys: String, CodingKey { case id, createdAt = "created_at", action, admin, target, detail }
}

// MARK: - Feedback

public enum FeedbackStatus: String, LenientEnum, Sendable, Equatable, CaseIterable {
    case new, handled, unknown

    public static var allCases: [FeedbackStatus] { [.new, .handled] }
}

public struct AdminFeedbackItem: Codable, Sendable, Equatable, Identifiable {
    public struct Handler: Codable, Sendable, Equatable {
        public let id: String
        public let username: String?
    }

    public let id: Int
    public let createdAt: String
    public let subject: String
    public let message: String
    public let contactEmail: String?
    public let displayName: String?
    public let status: FeedbackStatus
    public let handledAt: String?
    public let notes: String?
    public let emailSent: Bool
    public let user: AdminActor?
    public let handledBy: Handler?

    enum CodingKeys: String, CodingKey {
        case id, createdAt = "created_at", subject, message, contactEmail = "contact_email", displayName = "display_name"
        case status, handledAt = "handled_at", notes, emailSent = "email_sent", user, handledBy = "handled_by"
    }
}

public struct AdminFeedbackPage: Codable, Sendable, Equatable {
    public struct Counts: Codable, Sendable, Equatable {
        public let new: Int
        public let handled: Int
    }

    public let total: Int
    public let items: [AdminFeedbackItem]
    public let counts: Counts
}

/// `PATCH /admin/feedback/{id}`: `notes: nil` leaves them alone; `clearNotes` sends `null`.
public struct AdminFeedbackPatch: Codable, Sendable, Equatable {
    public var status: FeedbackStatus?
    public var notes: String?
    public var clearNotes = false

    public init(status: FeedbackStatus? = nil, notes: String? = nil, clearNotes: Bool = false) {
        self.status = status
        self.notes = notes
        self.clearNotes = clearNotes
    }

    enum CodingKeys: String, CodingKey { case status, notes }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(status, forKey: .status)
        if clearNotes { try c.encodeNil(forKey: .notes) } else { try c.encodeIfPresent(notes, forKey: .notes) }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decodeIfPresent(FeedbackStatus.self, forKey: .status)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        clearNotes = c.contains(.notes) && notes == nil
    }
}

public struct AdminFeedbackPatchResult: Codable, Sendable, Equatable {
    public let message: String
    public let item: AdminFeedbackItem?
}

// MARK: - CPUs

public struct AdminCPURow: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let cpuType: String
    public let displayName: String
    public let color: String
    public let description: String?
    public let isPremium: Bool
    public let createdAt: String?
    public let usageCount: Int

    enum CodingKeys: String, CodingKey {
        case id, cpuType = "cpu_type", displayName = "display_name", color, description, isPremium = "is_premium"
        case createdAt = "created_at", usageCount = "usage_count"
    }

    public init(id: Int, cpuType: String, displayName: String, color: String, description: String?, isPremium: Bool,
                createdAt: String?, usageCount: Int) {
        self.id = id
        self.cpuType = cpuType
        self.displayName = displayName
        self.color = color
        self.description = description
        self.isPremium = isPremium
        self.createdAt = createdAt
        self.usageCount = usageCount
    }
}

public struct AdminCPUCreate: Codable, Sendable, Equatable {
    public let id: Int
    public let cpuType: String
    public let displayName: String
    public let color: String
    public let description: String?
    public let isPremium: Bool

    public init(id: Int, cpuType: String, displayName: String, color: String, description: String? = nil, isPremium: Bool = false) {
        self.id = id
        self.cpuType = cpuType
        self.displayName = displayName
        self.color = color
        self.description = description
        self.isPremium = isPremium
    }

    enum CodingKeys: String, CodingKey {
        case id, cpuType = "cpu_type", displayName = "display_name", color, description, isPremium = "is_premium"
    }
}

public struct AdminCPUPatch: Codable, Sendable, Equatable {
    public var displayName: String?
    public var color: String?
    public var description: String?
    public var isPremium: Bool?

    public init(displayName: String? = nil, color: String? = nil, description: String? = nil, isPremium: Bool? = nil) {
        self.displayName = displayName
        self.color = color
        self.description = description
        self.isPremium = isPremium
    }

    enum CodingKeys: String, CodingKey { case displayName = "display_name", color, description, isPremium = "is_premium" }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(displayName, forKey: .displayName)
        try c.encodeIfPresent(color, forKey: .color)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(isPremium, forKey: .isPremium)
    }
}

public struct AdminCPUStats: Codable, Sendable, Equatable, Identifiable {
    public struct DayCount: Codable, Sendable, Equatable, Identifiable {
        public let date: String
        public let count: Int
        public var id: String { date }
    }

    public let id: Int
    public let cpuType: String
    public let displayName: String
    public let gamesTotal: Int
    public let gamesCompleted: Int
    public let humanWins: Int
    public let cpuWins: Int
    public let draws: Int
    public let humanWinRate: Double?
    public let avgHumanThinkS: Double?
    public let thinkSamples: Int
    public let usageByDay: [DayCount]

    enum CodingKeys: String, CodingKey {
        case id, cpuType = "cpu_type", displayName = "display_name", gamesTotal = "games_total", gamesCompleted = "games_completed"
        case humanWins = "human_wins", cpuWins = "cpu_wins", draws, humanWinRate = "human_win_rate"
        case avgHumanThinkS = "avg_human_think_s", thinkSamples = "think_samples", usageByDay = "usage_by_day"
    }
}

public struct AdminCPUStatsResponse: Codable, Sendable, Equatable {
    public let days: Int
    public let tz: String
    public let items: [AdminCPUStats]
}

public struct AdminTestMove: Codable, Sendable, Equatable {
    /// What the engine tiers report with the move (`src/ai/engine_move.py`); absent for heuristics.
    public struct Engine: Codable, Sendable, Equatable {
        public let mode: String?
        public let fallback: Bool?
        public let reason: String?
        public let depth: Int?
        public let nodes: Int?
        public let deadlineMs: Int?

        public init(mode: String?, fallback: Bool?, reason: String? = nil, depth: Int? = nil, nodes: Int? = nil, deadlineMs: Int? = nil) {
            self.mode = mode
            self.fallback = fallback
            self.reason = reason
            self.depth = depth
            self.nodes = nodes
            self.deadlineMs = deadlineMs
        }

        enum CodingKeys: String, CodingKey { case mode, fallback, reason, depth, nodes, deadlineMs = "deadline_ms" }
    }

    public let cpuType: String
    public let row: Int
    public let col: Int
    public let latencyMs: Double
    public let message: String
    public let engine: Engine?

    public init(cpuType: String, row: Int, col: Int, latencyMs: Double, message: String, engine: Engine? = nil) {
        self.cpuType = cpuType
        self.row = row
        self.col = col
        self.latencyMs = latencyMs
        self.message = message
        self.engine = engine
    }

    enum CodingKeys: String, CodingKey { case cpuType = "cpu_type", row, col, latencyMs = "latency_ms", message, engine }
}

/// `POST /admin/cpus/{type}/test-move` body: board 4–20 (engine tiers 6–12), deadline 50–10000 ms.
public struct AdminTestMoveRequest: Codable, Sendable, Equatable {
    public var boardSize: Int?
    public var deadlineMs: Int?

    public init(boardSize: Int? = nil, deadlineMs: Int? = nil) {
        self.boardSize = boardSize
        self.deadlineMs = deadlineMs
    }

    enum CodingKeys: String, CodingKey { case boardSize = "board_size", deadlineMs = "deadline_ms" }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(boardSize, forKey: .boardSize)
        try c.encodeIfPresent(deadlineMs, forKey: .deadlineMs)
    }
}

/// `{items: [...]}` wrappers (`/admin/cpus`).
public struct AdminItems<Item: Codable & Sendable & Equatable>: Codable, Sendable, Equatable {
    public let items: [Item]
}
