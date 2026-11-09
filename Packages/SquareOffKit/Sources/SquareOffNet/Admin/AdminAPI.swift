import Foundation

/// The superadmin console's REST API (`/api/admin/*`, web `services/adminAPI.ts`). Every route
/// needs a session whose current role is `superadmin`; the server answers 403 otherwise, and
/// 429 past 180 reads a minute or 60 writes an hour.
public protocol AdminAPI: Sendable {
    // Overview
    func health(refresh: Bool) async throws -> AdminHealth
    func timeseries(days: Int, tz: String?) async throws -> AdminTimeseries
    func live() async throws -> AdminLiveSnapshot

    // Users
    func users(_ query: AdminUserQuery) async throws -> Paged<AdminUserRow>
    func userOverview(id: String) async throws -> AdminUserOverview
    func userGames(id: String, page: PageRequest) async throws -> Paged<AdminUserGameRow>
    func userAudit(id: String, page: PageRequest) async throws -> Paged<AdminAuditRow>
    func patchUser(id: String, _ patch: AdminUserPatch) async throws -> MessageResponse
    func resetPassword(id: String, newPassword: String) async throws -> MessageResponse
    func forceLogout(id: String) async throws -> AdminForceLogoutResult

    // Games
    func games(_ query: AdminGameQuery) async throws -> Paged<AdminGameRow>
    /// `GET /admin/games/{id}/replay`: any game, finished or not (the same payload as `/replay`).
    func replay(gameID: Int) async throws -> GameReplayPayload

    // Audit
    func audit(_ query: AdminAuditQuery) async throws -> Paged<AdminAuditRow>

    // Feedback
    func feedback(status: FeedbackStatus?, page: PageRequest) async throws -> AdminFeedbackPage
    func patchFeedback(id: Int, _ patch: AdminFeedbackPatch) async throws -> AdminFeedbackPatchResult

    // CPUs
    func cpus() async throws -> [AdminCPURow]
    func cpuStats(days: Int, tz: String?) async throws -> AdminCPUStatsResponse
    func testMove(cpuType: String, boardSize: Int?) async throws -> AdminTestMove
    func createCPU(_ body: AdminCPUCreate) async throws -> MessageResponse
    func patchCPU(id: Int, _ patch: AdminCPUPatch) async throws -> MessageResponse
    func deleteCPU(id: Int) async throws -> MessageResponse
}

/// `?limit=&offset=`; lists page 50 at a time like the web.
public struct PageRequest: Sendable, Equatable {
    public var limit: Int
    public var offset: Int

    public init(limit: Int = 50, offset: Int = 0) {
        self.limit = limit
        self.offset = offset
    }

    public static func page(_ index: Int, size: Int = 50) -> PageRequest { PageRequest(limit: size, offset: index * size) }

    var queryItems: [URLQueryItem] {
        [URLQueryItem(name: "limit", value: String(limit)), URLQueryItem(name: "offset", value: String(offset))]
    }
}

/// `GET /admin/users` parameters (web `AdminUserListParams`); nils are left out of the URL.
public struct AdminUserQuery: Sendable, Equatable {
    public enum Sort: String, Sendable, Equatable, CaseIterable {
        case createdAt = "created_at", lastLoginAt = "last_login_at", username, gamesPlayed = "games_played"
    }

    public var q: String?
    public var sort: Sort
    public var dir: SortDir
    public var role: AppRole?
    public var active: Bool?
    public var provider: AuthProvider?
    public var hasPlayed: Bool?
    public var page: PageRequest

    public init(q: String? = nil, sort: Sort = .createdAt, dir: SortDir = .desc, role: AppRole? = nil, active: Bool? = nil,
                provider: AuthProvider? = nil, hasPlayed: Bool? = nil, page: PageRequest = PageRequest()) {
        self.q = q
        self.sort = sort
        self.dir = dir
        self.role = role
        self.active = active
        self.provider = provider
        self.hasPlayed = hasPlayed
        self.page = page
    }

    public var hasFilters: Bool { role != nil || active != nil || provider != nil || hasPlayed != nil }

    public var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let q = q?.trimmingCharacters(in: .whitespaces), !q.isEmpty { items.append(URLQueryItem(name: "q", value: q)) }
        items.append(URLQueryItem(name: "sort", value: sort.rawValue))
        items.append(URLQueryItem(name: "dir", value: dir.rawValue))
        if let role { items.append(URLQueryItem(name: "role", value: role.rawValue)) }
        if let active { items.append(URLQueryItem(name: "active", value: String(active))) }
        if let provider { items.append(URLQueryItem(name: "provider", value: provider.rawValue)) }
        if let hasPlayed { items.append(URLQueryItem(name: "has_played", value: String(hasPlayed))) }
        return items + page.queryItems
    }
}

/// `GET /admin/games` parameters (web `AdminGameListParams`). `to` is exclusive.
public struct AdminGameQuery: Sendable, Equatable {
    public enum GameType: String, Sendable, Equatable, CaseIterable { case local, online }

    public var type: GameType?
    public var cpuType: String?
    public var boardSize: Int?
    public var timer: Int?
    public var from: String?
    public var to: String?
    public var winner: AdminGameWinnerFilter?
    public var minDuration: Int?
    public var sort: AdminGameSort
    public var dir: SortDir
    public var page: PageRequest

    public init(type: GameType? = nil, cpuType: String? = nil, boardSize: Int? = nil, timer: Int? = nil, from: String? = nil,
                to: String? = nil, winner: AdminGameWinnerFilter? = nil, minDuration: Int? = nil, sort: AdminGameSort = .startTime,
                dir: SortDir = .desc, page: PageRequest = PageRequest()) {
        self.type = type
        self.cpuType = cpuType
        self.boardSize = boardSize
        self.timer = timer
        self.from = from
        self.to = to
        self.winner = winner
        self.minDuration = minDuration
        self.sort = sort
        self.dir = dir
        self.page = page
    }

    public var hasFilters: Bool {
        type != nil || cpuType != nil || boardSize != nil || timer != nil || from != nil || to != nil || winner != nil || minDuration != nil
    }

    public var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let type { items.append(URLQueryItem(name: "type", value: type.rawValue)) }
        if let cpuType { items.append(URLQueryItem(name: "cpu_type", value: cpuType)) }
        if let boardSize { items.append(URLQueryItem(name: "board_size", value: String(boardSize))) }
        if let timer { items.append(URLQueryItem(name: "timer", value: String(timer))) }
        if let from { items.append(URLQueryItem(name: "from", value: from)) }
        if let to { items.append(URLQueryItem(name: "to", value: to)) }
        if let winner { items.append(URLQueryItem(name: "winner", value: winner.rawValue)) }
        if let minDuration { items.append(URLQueryItem(name: "min_duration", value: String(minDuration))) }
        items.append(URLQueryItem(name: "sort", value: sort.rawValue))
        items.append(URLQueryItem(name: "dir", value: dir.rawValue))
        return items + page.queryItems
    }
}

/// `GET /admin/audit` parameters. The id filters must be UUIDs (the server validates them).
public struct AdminAuditQuery: Sendable, Equatable {
    public var action: AdminAuditAction?
    public var adminID: String?
    public var targetID: String?
    public var from: String?
    public var to: String?
    public var page: PageRequest

    public init(action: AdminAuditAction? = nil, adminID: String? = nil, targetID: String? = nil, from: String? = nil,
                to: String? = nil, page: PageRequest = PageRequest()) {
        self.action = action
        self.adminID = adminID
        self.targetID = targetID
        self.from = from
        self.to = to
        self.page = page
    }

    public var hasFilters: Bool { action != nil || adminID != nil || targetID != nil || from != nil || to != nil }

    public var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let action { items.append(URLQueryItem(name: "action", value: action.rawValue)) }
        if let adminID { items.append(URLQueryItem(name: "admin_id", value: adminID)) }
        if let targetID { items.append(URLQueryItem(name: "target_id", value: targetID)) }
        if let from { items.append(URLQueryItem(name: "from", value: from)) }
        if let to { items.append(URLQueryItem(name: "to", value: to)) }
        return items + page.queryItems
    }
}

/// URLSession client for `/api/admin/*`, sharing the player API's session and token.
public struct LiveAdminAPI: AdminAPI {
    private let client: RESTClient

    public init(environment: APIEnvironment, session: URLSession = .shared, tokenProvider: (any TokenProvider)? = nil,
                onSessionEnded: (@Sendable (SessionEndReason) -> Void)? = nil) {
        client = RESTClient(baseURL: environment.baseURL, session: session, tokenProvider: tokenProvider,
                            onSessionEnded: onSessionEnded)
    }

    private func tzItems(_ tz: String?) -> [URLQueryItem] {
        tz.map { [URLQueryItem(name: "tz", value: $0)] } ?? []
    }

    public func health(refresh: Bool) async throws -> AdminHealth {
        try await client.send("GET", "admin/health", query: refresh ? [URLQueryItem(name: "refresh", value: "true")] : [])
    }

    public func timeseries(days: Int, tz: String?) async throws -> AdminTimeseries {
        try await client.send("GET", "admin/stats/timeseries", query: [URLQueryItem(name: "days", value: String(days))] + tzItems(tz))
    }

    public func live() async throws -> AdminLiveSnapshot {
        try await client.send("GET", "admin/live")
    }

    public func users(_ query: AdminUserQuery) async throws -> Paged<AdminUserRow> {
        try await client.send("GET", "admin/users", query: query.queryItems)
    }

    public func userOverview(id: String) async throws -> AdminUserOverview {
        try await client.send("GET", "admin/users/\(id)/overview")
    }

    public func userGames(id: String, page: PageRequest) async throws -> Paged<AdminUserGameRow> {
        try await client.send("GET", "admin/users/\(id)/games", query: page.queryItems)
    }

    public func userAudit(id: String, page: PageRequest) async throws -> Paged<AdminAuditRow> {
        try await client.send("GET", "admin/users/\(id)/audit", query: page.queryItems)
    }

    public func patchUser(id: String, _ patch: AdminUserPatch) async throws -> MessageResponse {
        try await client.send("PATCH", "admin/users/\(id)", body: patch)
    }

    public func resetPassword(id: String, newPassword: String) async throws -> MessageResponse {
        try await client.send("POST", "admin/users/\(id)/reset-password", body: ["new_password": newPassword])
    }

    public func forceLogout(id: String) async throws -> AdminForceLogoutResult {
        try await client.send("POST", "admin/users/\(id)/force-logout")
    }

    public func games(_ query: AdminGameQuery) async throws -> Paged<AdminGameRow> {
        try await client.send("GET", "admin/games", query: query.queryItems)
    }

    public func replay(gameID: Int) async throws -> GameReplayPayload {
        try await client.send("GET", "admin/games/\(gameID)/replay")
    }

    public func audit(_ query: AdminAuditQuery) async throws -> Paged<AdminAuditRow> {
        try await client.send("GET", "admin/audit", query: query.queryItems)
    }

    public func feedback(status: FeedbackStatus?, page: PageRequest) async throws -> AdminFeedbackPage {
        let items = (status.map { [URLQueryItem(name: "status", value: $0.rawValue)] } ?? []) + page.queryItems
        return try await client.send("GET", "admin/feedback", query: items)
    }

    public func patchFeedback(id: Int, _ patch: AdminFeedbackPatch) async throws -> AdminFeedbackPatchResult {
        try await client.send("PATCH", "admin/feedback/\(id)", body: patch)
    }

    public func cpus() async throws -> [AdminCPURow] {
        let wrapped: AdminItems<AdminCPURow> = try await client.send("GET", "admin/cpus")
        return wrapped.items
    }

    public func cpuStats(days: Int, tz: String?) async throws -> AdminCPUStatsResponse {
        try await client.send("GET", "admin/cpus/stats", query: [URLQueryItem(name: "days", value: String(days))] + tzItems(tz))
    }

    public func testMove(cpuType: String, boardSize: Int?) async throws -> AdminTestMove {
        let body: [String: Int] = boardSize.map { ["board_size": $0] } ?? [:]
        return try await client.send("POST", "admin/cpus/\(cpuType)/test-move", body: body)
    }

    public func createCPU(_ body: AdminCPUCreate) async throws -> MessageResponse {
        try await client.send("POST", "admin/cpus", body: body)
    }

    public func patchCPU(id: Int, _ patch: AdminCPUPatch) async throws -> MessageResponse {
        try await client.send("PATCH", "admin/cpus/\(id)", body: patch)
    }

    public func deleteCPU(id: Int) async throws -> MessageResponse {
        try await client.send("DELETE", "admin/cpus/\(id)")
    }
}
