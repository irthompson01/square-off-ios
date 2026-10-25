import Foundation
import SquareOffCore

/// A deterministic in-memory console for the admin app's demos and tests (a port of the web's
/// `e2e/fixtures/data.ts` generators): 42 users, 120 games with seats, 6 CPUs, feedback, an
/// audit log, health, a 90-day timeseries and a live snapshot. Writes mutate it and append
/// audit rows; every call answers 403 unless the signed-in mock user is a superadmin.
public actor MockAdminAPI: AdminAPI {
    public static let userCount = 42
    public static let gameCount = 120

    private let accounts: MockSquareOffAPI?
    private let latency: Duration
    private let now: Date

    private var users: [AdminUserDetail] = []
    private var gamesPlayed: [String: Int] = [:]
    private var games: [AdminGameRow] = []
    private var cpus: [AdminCPURow] = []
    private var feedback: [AdminFeedbackItem] = []
    private var auditRows: [AdminAuditRow] = []
    private var seeded = false
    private var nextAuditID = 1

    public init(accounts: MockSquareOffAPI? = nil, latency: Duration = .milliseconds(120), now: Date = .now) {
        self.accounts = accounts
        self.latency = latency
        self.now = now
    }

    // MARK: Access

    /// The signed-in mock user when they are a superadmin; 401 when nobody is signed in.
    private func requireAdmin() async throws -> String {
        try await pause()
        seed()
        guard let accounts else { return Self.userID(1) }
        guard let role = await accounts.currentRole(), let id = await accounts.currentUserID() else {
            throw APIError.http(status: 401, body: #"{"detail":"No access token provided"}"#)
        }
        guard role == "superadmin" else {
            throw APIError.http(status: 403, body: #"{"detail":"SuperAdmin access required"}"#)
        }
        return id
    }

    private func pause() async throws {
        if latency > .zero { try await Task.sleep(for: latency) }
    }

    // MARK: Overview

    public func health(refresh: Bool) async throws -> AdminHealth {
        _ = try await requireAdmin()
        return AdminHealth(
            db: .init(ok: true, latencyMs: refresh ? 3.4 : 2.1, pool: .init(min: 1, max: 10, inUse: 1, idle: 2), error: nil),
            model: .init(ok: true, latencyMs: 41, cached: !refresh, checkedAt: Self.iso(now.addingTimeInterval(-90)),
                         move: .init(row: 3, col: 4), error: nil),
            mail: .init(configured: true, server: "smtp.example.com"),
            app: .init(version: "1.4.0", buildSha: "17f5c51", env: "mock", startedAt: Self.iso(now.addingTimeInterval(-6 * 3600)),
                       uptimeS: 6 * 3600, python: "3.12.6", fastapi: "0.115.0", rateLimitStorage: "memory")
        )
    }

    public func timeseries(days: Int, tz: String?) async throws -> AdminTimeseries {
        _ = try await requireAdmin()
        let count = max(1, min(days, 365))
        var rng = SplitMix64(seed: 0xADA1)
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: now)
        let points: [AdminTimeseriesPoint] = (0..<count).reversed().map { back in
            let date = calendar.date(byAdding: .day, value: -back, to: today)!
            let weekday = calendar.component(.weekday, from: date)
            let boost = (weekday == 1 || weekday == 7) ? 6 : 0
            let local = 4 + boost + Int(rng.next() % 6)
            let online = 2 + Int(rng.next() % 5)
            let cpu = 5 + boost + Int(rng.next() % 7)
            return AdminTimeseriesPoint(date: Self.day(date), gamesStarted: .init(local: local, online: online, cpu: cpu),
                                        gamesCompleted: Int(Double(local + online + cpu) * 0.78), newUsers: Int(rng.next() % 4),
                                        newGuestSessions: 3 + Int(rng.next() % 9))
        }
        let started = points.reduce(0) { $0 + $1.gamesStarted.total }
        let completed = points.reduce(0) { $0 + $1.gamesCompleted }
        return AdminTimeseries(
            days: count, tz: tz ?? "UTC", from: points.first!.date, to: points.last!.date, series: points,
            totals: .init(gamesStarted: started, gamesCompleted: completed,
                          completionRate: started > 0 ? (Double(completed) / Double(started) * 1000).rounded() / 10 : nil,
                          medianDurationMin: 6.5, medianDurationMinOnline: 9.2, dau: 7, wau: 21, mau: 38,
                          registeredUsers: users.count,
                          providerMix: [.init(provider: "password", count: 24), .init(provider: "google", count: 11),
                                        .init(provider: "apple", count: 5), .init(provider: "github", count: 2)],
                          guestVsRegisteredParticipants: .init(user: 140, guest: 66, cpu: 90))
        )
    }

    public func live() async throws -> AdminLiveSnapshot {
        _ = try await requireAdmin()
        let rooms = [
            AdminLiveRoom(roomCode: 4821, phase: .playing, boardSize: 8, timer: 20, gameId: 1180, matchInProgress: true,
                          hostConnected: true, hostAwaySeconds: nil,
                          players: [.init(slot: 1, name: "pat", isCPU: false, playerId: Self.userID(2), score: 14, connected: true, awaySeconds: nil),
                                    .init(slot: 2, name: "Guest", isCPU: false, playerId: "guest-77", score: 9, connected: true, awaySeconds: nil)],
                          guestConnections: 1, spectatorCount: 2, turnIndex: 0, movesPlayed: 23, gameOver: false),
            AdminLiveRoom(roomCode: 7730, phase: .hostAway, boardSize: 6, timer: 0, gameId: 1181, matchInProgress: true,
                          hostConnected: false, hostAwaySeconds: 32,
                          players: [.init(slot: 1, name: "sam", isCPU: false, playerId: Self.userID(5), score: 4, connected: false, awaySeconds: 32),
                                    .init(slot: 2, name: "kai", isCPU: false, playerId: Self.userID(9), score: 6, connected: true, awaySeconds: nil)],
                          guestConnections: 1, spectatorCount: 0, turnIndex: 1, movesPlayed: 11, gameOver: false),
            AdminLiveRoom(roomCode: 1502, phase: .lobby, boardSize: 10, timer: 30, gameId: nil, matchInProgress: false,
                          hostConnected: true, hostAwaySeconds: nil,
                          players: [.init(slot: 1, name: "lee", isCPU: false, playerId: Self.userID(12), score: 0, connected: true, awaySeconds: nil)],
                          guestConnections: 0, spectatorCount: 0, turnIndex: nil, movesPlayed: 0, gameOver: false),
            AdminLiveRoom(roomCode: 9044, phase: .gameOver, boardSize: 8, timer: 0, gameId: 1177, matchInProgress: false,
                          hostConnected: true, hostAwaySeconds: nil,
                          players: [.init(slot: 1, name: "ian", isCPU: false, playerId: Self.userID(1), score: 36, connected: true, awaySeconds: nil),
                                    .init(slot: 2, name: "pat", isCPU: false, playerId: Self.userID(2), score: 28, connected: true, awaySeconds: nil)],
                          guestConnections: 1, spectatorCount: 1, turnIndex: nil, movesPlayed: 64, gameOver: true),
        ]
        return AdminLiveSnapshot(
            generatedAt: Self.iso(now), websocket: .init(connections: 9, inRooms: 7), rooms: rooms,
            openRooms: [AdminLiveOpenRoom(roomCode: 1502, boardSize: 10, timer: 30, slotsFilled: 1, slotsMax: 4, listed: true,
                                          hostLabel: "lee", hostKey: "hk-lee", gameId: nil, createdAt: now.timeIntervalSince1970 - 95,
                                          ageS: 95, heartbeatAgeS: 4)],
            matchQueue: .init(tickets: 1, oldestWaitS: 42, pairsPending: 0,
                              items: [AdminLiveQueueItem(ticketId: "t-6f3a", boardSize: 8, timer: 20, waitS: 42, assignedRoomCode: nil,
                                                         shouldCreateRoom: false, acknowledged: true)])
        )
    }

    // MARK: Users

    public func users(_ query: AdminUserQuery) async throws -> Paged<AdminUserRow> {
        _ = try await requireAdmin()
        var rows = users.map(row(for:))
        if let q = query.q?.trimmingCharacters(in: .whitespaces).lowercased(), !q.isEmpty {
            rows = rows.filter { $0.email.lowercased().contains(q) || $0.username.lowercased().contains(q) }
        }
        if let role = query.role { rows = rows.filter { $0.appRole == role } }
        if let active = query.active { rows = rows.filter { $0.isActive == active } }
        if let provider = query.provider {
            rows = rows.filter { ($0.oauthProvider ?? "password") == provider.rawValue }
        }
        if let hasPlayed = query.hasPlayed { rows = rows.filter { ($0.gamesPlayed > 0) == hasPlayed } }
        rows.sort { a, b in
            let ascending: Bool
            switch query.sort {
            case .createdAt: ascending = (a.createdAt ?? "") < (b.createdAt ?? "")
            case .lastLoginAt: ascending = (a.lastLoginAt ?? "") < (b.lastLoginAt ?? "")
            case .username: ascending = a.username.lowercased() < b.username.lowercased()
            case .gamesPlayed: ascending = a.gamesPlayed < b.gamesPlayed
            }
            return query.dir == .asc ? ascending : !ascending
        }
        return Paged(total: rows.count, items: Self.slice(rows, query.page))
    }

    public func userOverview(id: String) async throws -> AdminUserOverview {
        _ = try await requireAdmin()
        guard let user = users.first(where: { $0.id == id }) else { throw Self.notFound("User not found") }
        let played = gamesPlayed[id] ?? 0
        let stats: PlayerStatsView? = played > 0 ? PlayerStatsView(
            playerId: id, username: user.username, email: user.email, firstName: user.firstName, lastName: user.lastName,
            color: user.color, createdAt: user.createdAt ?? "", totalGamesPlayed: played, gamesWon: played * 55 / 100,
            gamesLost: played - played * 55 / 100, winPercentage: 55, avgGameDuration: 412, highestScore: 148,
            avgFinalScore: 62.5, localGamesPlayed: played * 2 / 3) : nil
        let identities: [AdminUserIdentity] = user.oauthProvider.map {
            [AdminUserIdentity(id: 1, provider: $0, providerSub: "sub-\(user.username)", providerEmail: user.email, createdAt: user.createdAt ?? Self.iso(now))]
        } ?? []
        return AdminUserOverview(user: user, stats: stats, gamesPlayed: played, lastPlayedAt: played > 0 ? Self.naive(now.addingTimeInterval(-3600 * 5)) : nil,
                                 gamesAbandoned: played / 10, identities: identities,
                                 entitlements: user.appRole == .superadmin ? [AdminUserEntitlement(id: 1, entitlementType: "premium_cpu", entitlementValue: "all", grantedAt: Self.iso(now.addingTimeInterval(-86_400 * 30)), expiresAt: nil, source: "admin")] : [],
                                 auditCount: auditRows.filter { $0.target?.id == id }.count,
                                 feedbackCount: feedback.filter { $0.user?.id == id }.count)
    }

    public func userGames(id: String, page: PageRequest) async throws -> Paged<AdminUserGameRow> {
        _ = try await requireAdmin()
        let mine = games.filter { $0.participants.contains { $0.userId == id } }
        let rows = mine.map { game -> AdminUserGameRow in
            let me = game.participants.first { $0.userId == id }
            let result: AdminUserGameResult = game.endTime == nil ? .unfinished : (me?.isWinner == true ? .win : (game.winnerType == nil ? .tie : .loss))
            let opponents = game.participants.filter { $0.userId != id }.map(\.displayName).joined(separator: ", ")
            return AdminUserGameRow(gameId: game.id, gameType: game.type, startTime: game.startTime, endTime: game.endTime,
                                    boardSize: game.boardSize, timer: game.timer, myScore: me?.finalScore, result: result,
                                    opponentLabel: opponents, replayAvailable: game.endTime != nil, replayUrl: game.endTime != nil ? "/api/\(game.id)/replay" : nil)
        }
        return Paged(total: rows.count, items: Self.slice(rows, page))
    }

    public func userAudit(id: String, page: PageRequest) async throws -> Paged<AdminAuditRow> {
        _ = try await requireAdmin()
        let rows = auditRows.filter { $0.target?.id == id || $0.admin.id == id }
        return Paged(total: rows.count, items: Self.slice(rows, page))
    }

    public func patchUser(id: String, _ patch: AdminUserPatch) async throws -> MessageResponse {
        let adminID = try await requireAdmin()
        guard let index = users.firstIndex(where: { $0.id == id }) else { throw Self.notFound("User not found") }
        guard !patch.isEmpty else { throw APIError.http(status: 422, body: #"{"detail":[{"msg":"No fields to update"}]}"#) }
        if id == adminID, patch.isActive == false || patch.appRole == .standard {
            throw APIError.http(status: 400, body: #"{"detail":"Cannot deactivate or demote your own account"}"#)
        }
        let old = users[index]
        var bumped = false
        if patch.isActive == false, old.isActive { bumped = true }
        users[index] = AdminUserDetail(
            id: old.id, email: old.email, username: patch.username ?? old.username, firstName: patch.firstName ?? old.firstName,
            lastName: patch.lastName ?? old.lastName, color: patch.color ?? old.color, appRole: patch.appRole ?? old.appRole,
            isActive: patch.isActive ?? old.isActive, createdAt: old.createdAt, registered: old.registered, isCpu: old.isCpu,
            lastLoginAt: old.lastLoginAt, sessionVersion: old.sessionVersion + (bumped ? 1 : 0), updatedAt: Self.naive(now),
            oauthProvider: old.oauthProvider, profilePictureUrl: old.profilePictureUrl)
        var detail: [String: JSONValue] = [:]
        if let role = patch.appRole { detail["app_role"] = .string(role.rawValue) }
        if let active = patch.isActive { detail["is_active"] = .bool(active) }
        if bumped { detail["session_version_bumped"] = .bool(true) }
        for (key, value) in [("first_name", patch.firstName), ("last_name", patch.lastName), ("username", patch.username), ("color", patch.color)] {
            if let value { detail[key] = .string(value) }
        }
        audit(adminID: adminID, targetID: id, action: .userPatch, detail: .object(detail))
        return MessageResponse(message: "User updated")
    }

    public func resetPassword(id: String, newPassword: String) async throws -> MessageResponse {
        let adminID = try await requireAdmin()
        guard users.contains(where: { $0.id == id }) else { throw Self.notFound("User not found") }
        guard newPassword.count >= 8 else {
            throw APIError.http(status: 422, body: #"{"detail":[{"msg":"String should have at least 8 characters"}]}"#)
        }
        audit(adminID: adminID, targetID: id, action: .resetPassword, detail: nil)
        return MessageResponse(message: "Password updated")
    }

    public func forceLogout(id: String) async throws -> AdminForceLogoutResult {
        let adminID = try await requireAdmin()
        guard let index = users.firstIndex(where: { $0.id == id }) else { throw Self.notFound("User not found") }
        if id == adminID { throw APIError.http(status: 400, body: #"{"detail":"Cannot sign out your own account"}"#) }
        let old = users[index]
        let version = old.sessionVersion + 1
        users[index] = AdminUserDetail(
            id: old.id, email: old.email, username: old.username, firstName: old.firstName, lastName: old.lastName, color: old.color,
            appRole: old.appRole, isActive: old.isActive, createdAt: old.createdAt, registered: old.registered, isCpu: old.isCpu,
            lastLoginAt: old.lastLoginAt, sessionVersion: version, updatedAt: old.updatedAt, oauthProvider: old.oauthProvider,
            profilePictureUrl: old.profilePictureUrl)
        audit(adminID: adminID, targetID: id, action: .forceLogout, detail: .object(["session_version": .number(Double(version))]))
        return AdminForceLogoutResult(message: "Sessions revoked", sessionVersion: version)
    }

    // MARK: Games

    public func games(_ query: AdminGameQuery) async throws -> Paged<AdminGameRow> {
        _ = try await requireAdmin()
        var rows = games
        if let type = query.type { rows = rows.filter { $0.type == type.rawValue } }
        if let cpuType = query.cpuType { rows = rows.filter { $0.cpuType == cpuType } }
        if let boardSize = query.boardSize { rows = rows.filter { $0.boardSize == boardSize } }
        if let timer = query.timer { rows = rows.filter { $0.timer == timer } }
        if let from = query.from { rows = rows.filter { ($0.startTime ?? "") >= from } }
        if let to = query.to { rows = rows.filter { ($0.startTime ?? "") < to } }
        if let winner = query.winner {
            rows = rows.filter { game in
                switch winner {
                case .unfinished: game.endTime == nil
                case .draw: game.endTime != nil && game.winnerType == nil
                case .user: game.winnerType == .user
                case .guest: game.winnerType == .guest
                case .cpu: game.winnerType == .cpu
                }
            }
        }
        if let minDuration = query.minDuration { rows = rows.filter { ($0.durationSec ?? -1) >= minDuration } }
        rows.sort { a, b in
            let ascending: Bool
            switch query.sort {
            case .startTime: ascending = (a.startTime ?? "") < (b.startTime ?? "")
            case .endTime: ascending = (a.endTime ?? "") < (b.endTime ?? "")
            case .duration: ascending = (a.durationSec ?? -1) < (b.durationSec ?? -1)
            }
            return query.dir == .asc ? ascending : !ascending
        }
        return Paged(total: rows.count, items: Self.slice(rows, query.page))
    }

    public func replay(gameID: Int) async throws -> GameReplayPayload {
        _ = try await requireAdmin()
        guard let game = games.first(where: { $0.id == gameID }) else { throw Self.notFound("Game not found") }
        return Self.simulatedReplay(for: game)
    }

    // MARK: Audit

    public func audit(_ query: AdminAuditQuery) async throws -> Paged<AdminAuditRow> {
        _ = try await requireAdmin()
        var rows = auditRows
        if let action = query.action { rows = rows.filter { $0.action == action } }
        if let adminID = query.adminID { rows = rows.filter { $0.admin.id == adminID } }
        if let targetID = query.targetID { rows = rows.filter { $0.target?.id == targetID } }
        if let from = query.from { rows = rows.filter { $0.createdAt >= from } }
        if let to = query.to { rows = rows.filter { $0.createdAt < to } }
        return Paged(total: rows.count, items: Self.slice(rows, query.page))
    }

    // MARK: Feedback

    public func feedback(status: FeedbackStatus?, page: PageRequest) async throws -> AdminFeedbackPage {
        _ = try await requireAdmin()
        let rows = status.map { s in feedback.filter { $0.status == s } } ?? feedback
        return AdminFeedbackPage(total: rows.count, items: Self.slice(rows, page),
                                 counts: .init(new: feedback.filter { $0.status == .new }.count, handled: feedback.filter { $0.status == .handled }.count))
    }

    public func patchFeedback(id: Int, _ patch: AdminFeedbackPatch) async throws -> AdminFeedbackPatchResult {
        let adminID = try await requireAdmin()
        guard let index = feedback.firstIndex(where: { $0.id == id }) else { throw Self.notFound("Feedback not found") }
        guard patch.status != nil || patch.notes != nil || patch.clearNotes else {
            throw APIError.http(status: 422, body: #"{"detail":[{"msg":"Nothing to update"}]}"#)
        }
        let old = feedback[index]
        let status = patch.status ?? old.status
        let handledNow = status == .handled
        let admin = users.first { $0.id == adminID }
        let item = AdminFeedbackItem(
            id: old.id, createdAt: old.createdAt, subject: old.subject, message: old.message, contactEmail: old.contactEmail,
            displayName: old.displayName, status: status,
            handledAt: handledNow ? (old.handledAt ?? Self.iso(now)) : nil,
            notes: patch.clearNotes ? nil : (patch.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? old.notes),
            emailSent: old.emailSent, user: old.user,
            handledBy: handledNow ? (old.handledBy ?? .init(id: adminID, username: admin?.username)) : nil)
        feedback[index] = item
        var detail: [String: JSONValue] = ["feedback_id": .number(Double(id))]
        if let s = patch.status { detail["status"] = .string(s.rawValue) }
        if patch.notes != nil || patch.clearNotes { detail["notes_updated"] = .bool(true) }
        audit(adminID: adminID, targetID: old.user?.id, action: .feedbackPatch, detail: .object(detail))
        return AdminFeedbackPatchResult(message: "Feedback updated", item: item)
    }

    // MARK: CPUs

    public func cpus() async throws -> [AdminCPURow] {
        _ = try await requireAdmin()
        return cpus
    }

    public func cpuStats(days: Int, tz: String?) async throws -> AdminCPUStatsResponse {
        _ = try await requireAdmin()
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: now)
        var rng = SplitMix64(seed: UInt64(days))
        let items = cpus.map { cpu -> AdminCPUStats in
            let usage = (0..<days).reversed().map { back -> AdminCPUStats.DayCount in
                let date = calendar.date(byAdding: .day, value: -back, to: today)!
                return .init(date: Self.day(date), count: Int(rng.next() % UInt64(3 + cpu.id)))
            }
            let total = usage.reduce(0) { $0 + $1.count }
            let completed = total * 4 / 5
            let humanWins = completed * (70 - cpu.id * 8) / 100
            return AdminCPUStats(id: cpu.id, cpuType: cpu.cpuType, displayName: cpu.displayName, gamesTotal: total, gamesCompleted: completed,
                                 humanWins: humanWins, cpuWins: completed - humanWins - completed / 20, draws: completed / 20,
                                 humanWinRate: completed > 0 ? (Double(humanWins) / Double(completed) * 1000).rounded() / 10 : nil,
                                 avgHumanThinkS: 4.2 + Double(cpu.id), thinkSamples: completed * 20, usageByDay: usage)
        }
        return AdminCPUStatsResponse(days: days, tz: tz ?? "UTC", items: items)
    }

    public func testMove(cpuType: String, boardSize: Int?) async throws -> AdminTestMove {
        _ = try await requireAdmin()
        guard cpus.contains(where: { $0.cpuType == cpuType }) else { throw Self.notFound("CPU not found") }
        let size = boardSize ?? 8
        let game = Game(boardSize: size, players: [PlayerState(id: 1, name: "A", colorHex: "#4C8BF5"), PlayerState(id: 2, name: "B", colorHex: "#DD5144")])
        let strategy = CPULevel(rawValue: cpuType).flatMap(CPUStrategy.init(level:)) ?? .random
        let cell = strategy.chooseMove(in: game)
        return AdminTestMove(cpuType: cpuType, row: cell.row, col: cell.col, latencyMs: cpuType == "cnn" ? 38 : 2, message: "ok")
    }

    public func createCPU(_ body: AdminCPUCreate) async throws -> MessageResponse {
        let adminID = try await requireAdmin()
        guard !cpus.contains(where: { $0.id == body.id || $0.cpuType == body.cpuType }) else {
            throw APIError.http(status: 409, body: #"{"detail":"CPU id or type already exists"}"#)
        }
        cpus.append(AdminCPURow(id: body.id, cpuType: body.cpuType, displayName: body.displayName, color: body.color,
                                description: body.description, isPremium: body.isPremium, createdAt: Self.naive(now), usageCount: 0))
        audit(adminID: adminID, targetID: nil, action: .cpuCreate, detail: .object(["id": .number(Double(body.id)), "cpu_type": .string(body.cpuType)]))
        return MessageResponse(message: "CPU created")
    }

    public func patchCPU(id: Int, _ patch: AdminCPUPatch) async throws -> MessageResponse {
        let adminID = try await requireAdmin()
        guard let index = cpus.firstIndex(where: { $0.id == id }) else { throw Self.notFound("CPU not found") }
        let old = cpus[index]
        cpus[index] = AdminCPURow(id: old.id, cpuType: old.cpuType, displayName: patch.displayName ?? old.displayName,
                                  color: patch.color ?? old.color, description: patch.description ?? old.description,
                                  isPremium: patch.isPremium ?? old.isPremium, createdAt: old.createdAt, usageCount: old.usageCount)
        audit(adminID: adminID, targetID: nil, action: .cpuPatch, detail: .object(["id": .number(Double(id))]))
        return MessageResponse(message: "CPU updated")
    }

    public func deleteCPU(id: Int) async throws -> MessageResponse {
        let adminID = try await requireAdmin()
        guard let index = cpus.firstIndex(where: { $0.id == id }) else { throw Self.notFound("CPU not found") }
        guard cpus[index].usageCount == 0 else {
            throw APIError.http(status: 409, body: #"{"detail":"CPU has games in history and cannot be deleted"}"#)
        }
        cpus.remove(at: index)
        audit(adminID: adminID, targetID: nil, action: .cpuDelete, detail: .object(["id": .number(Double(id))]))
        return MessageResponse(message: "CPU deleted")
    }

    // MARK: Seeding

    public static func userID(_ n: Int) -> String { "00000000-0000-4000-8000-" + String(format: "%012d", n) }

    private static let names = ["ian", "pat", "sam", "kai", "lee", "max", "ava", "zoe", "eli", "mia", "noa", "ray"]

    private func seed() {
        guard !seeded else { return }
        seeded = true
        var rng = SplitMix64(seed: 0xA0D1_4242)
        let providers: [String?] = [nil, "google", nil, "apple", nil, "github", nil, nil]
        users = (1...Self.userCount).map { n in
            let name = Self.names[(n - 1) % Self.names.count] + (n > Self.names.count ? String(n) : "")
            let created = now.addingTimeInterval(-Double(400 - n * 9) * 86_400)
            let played = n % 7 == 0 ? 0 : Int(rng.next() % 40) + 1
            gamesPlayed[Self.userID(n)] = played
            return AdminUserDetail(
                id: Self.userID(n), email: "\(name)@example.com", username: name,
                firstName: n % 3 == 0 ? "" : name.prefix(1).uppercased() + name.dropFirst(), lastName: n % 3 == 0 ? "" : "T",
                color: ["#4C8BF5", "#DD5144", "#1DA462", "#FFCD46"][n % 4], appRole: n == 1 ? .superadmin : .standard,
                isActive: n != 8, createdAt: Self.naive(created), registered: true, isCpu: false,
                lastLoginAt: n % 5 == 0 ? nil : Self.iso(now.addingTimeInterval(-Double(n) * 5_000)),
                sessionVersion: n == 8 ? 1 : 0, updatedAt: nil, oauthProvider: providers[n % providers.count], profilePictureUrl: nil)
        }
        if accounts != nil {
            // The signed-in mock account (`demo`) sits in the directory too, so self-protection
            // rules and "handled by" apply to it.
            users.insert(AdminUserDetail(
                id: MockSquareOffAPI.demoUserID, email: MockSquareOffAPI.demoEmail, username: MockSquareOffAPI.demoUsername,
                firstName: "Demo", lastName: "Player", color: "#0583D2", appRole: .superadmin, isActive: true,
                createdAt: "2026-09-01T12:00:00", registered: true, isCpu: false, lastLoginAt: Self.iso(now.addingTimeInterval(-60)),
                sessionVersion: 0, updatedAt: nil, oauthProvider: nil, profilePictureUrl: nil), at: 0)
            gamesPlayed[MockSquareOffAPI.demoUserID] = 3
        }
        cpus = CPULevel.allCases.map { level in
            AdminCPURow(id: level.number, cpuType: level.cpuType, displayName: "Level \(level.number) · \(level.shortName)",
                        color: "#DD5144", description: level == .cnn ? "Convolutional net, 8×8 only" : nil, isPremium: level == .maxMinIO,
                        createdAt: Self.naive(now.addingTimeInterval(-200 * 86_400)), usageCount: level == .maxMinIO ? 0 : 30 + level.number * 11)
        }
        games = (1...Self.gameCount).map { n in
            let id = 1000 + n
            let online = n % 3 == 0
            let cpuGame = !online && n % 2 == 0
            let board = [6, 8, 8, 10, 12][n % 5]
            let timer = [0, 0, 20, 30][n % 4]
            let start = now.addingTimeInterval(-Double(n) * 7_200 - 600)
            let unfinished = n % 9 == 0
            let duration = unfinished ? nil : 180 + Int(rng.next() % 900)
            let userA = Self.userID(1 + n % Self.userCount)
            let userB = Self.userID(1 + (n * 7) % Self.userCount)
            let scoreA = Int(rng.next() % 60) + 5, scoreB = Int(rng.next() % 60) + 5
            let tie = n % 11 == 0
            var seats: [AdminGameParticipant] = [
                AdminGameParticipant(participantId: id * 10 + 1, participantType: .user, displayName: users[n % Self.userCount].username, color: "#4C8BF5",
                                     userId: userA, username: users[n % Self.userCount].username, guestId: nil, cpuDefinitionId: nil, cpuType: nil,
                                     finalScore: unfinished ? nil : scoreA, participantOrder: 0, isWinner: !unfinished && !tie && scoreA >= scoreB),
            ]
            if cpuGame {
                let level = CPULevel.allCases[n % CPULevel.allCases.count]
                seats.append(AdminGameParticipant(participantId: id * 10 + 2, participantType: .cpu, displayName: "CPU (\(level.shortName))", color: "#DD5144",
                                                  userId: nil, username: nil, guestId: nil, cpuDefinitionId: level.number, cpuType: level.cpuType,
                                                  finalScore: unfinished ? nil : scoreB, participantOrder: 1, isWinner: !unfinished && !tie && scoreB > scoreA))
            } else if online {
                seats.append(AdminGameParticipant(participantId: id * 10 + 2, participantType: .user, displayName: users[(n * 7) % Self.userCount].username, color: "#DD5144",
                                                  userId: userB, username: users[(n * 7) % Self.userCount].username, guestId: nil, cpuDefinitionId: nil, cpuType: nil,
                                                  finalScore: unfinished ? nil : scoreB, participantOrder: 1, isWinner: !unfinished && !tie && scoreB > scoreA))
            } else {
                seats.append(AdminGameParticipant(participantId: id * 10 + 2, participantType: .guest, displayName: "Guest", color: "#DD5144",
                                                  userId: nil, username: nil, guestId: "guest-\(n)", cpuDefinitionId: nil, cpuType: nil,
                                                  finalScore: unfinished ? nil : scoreB, participantOrder: 1, isWinner: !unfinished && !tie && scoreB > scoreA))
            }
            let winner = seats.first { $0.isWinner }
            return AdminGameRow(id: id, type: online ? "online" : "local", startTime: Self.naive(start),
                                endTime: duration.map { Self.naive(start.addingTimeInterval(Double($0))) }, boardSize: board, timer: timer,
                                winnerId: winner?.userId, winnerParticipantId: winner?.participantId, winnerDisplay: winner?.displayName,
                                scores: unfinished ? nil : .array([.number(Double(scoreA)), .number(Double(scoreB))]), isCpu: cpuGame,
                                cpuType: seats.last?.cpuType, participantCount: seats.count, durationSec: duration,
                                winnerType: winner?.participantType, participants: seats)
        }
        let subjects = ["Board doesn't load", "Love the new rulebook", "Timer runs out too fast", "Replay stuck at move 12", "Add a 14×14 board",
                        "Typo on the stats page", "Quick match never pairs", "Sound stays on after mute", "Dark tiles please", "Crash on rotate",
                        "Thanks!", "Colour picker too small"]
        feedback = subjects.enumerated().map { index, subject in
            let n = index + 1
            let handled = n % 3 == 0
            let sender = n % 4 == 0 ? nil : users[(n * 3) % Self.userCount]
            return AdminFeedbackItem(id: n, createdAt: Self.iso(now.addingTimeInterval(-Double(n) * 9_000)), subject: subject,
                                     message: "Steps: \(subject.lowercased()). Expected it to work; it didn't. iPhone 15, iOS 18.",
                                     contactEmail: n % 2 == 0 ? sender?.email : nil, displayName: sender?.username, status: handled ? .handled : .new,
                                     handledAt: handled ? Self.iso(now.addingTimeInterval(-Double(n) * 4_000)) : nil,
                                     notes: handled ? "Fixed in 1.4.1" : nil, emailSent: n % 5 != 0,
                                     user: sender.map { AdminActor(id: $0.id, username: $0.username, email: $0.email) },
                                     handledBy: handled ? .init(id: Self.userID(1), username: "ian") : nil)
        }
        let actions: [AdminAuditAction] = [.userPatch, .resetPassword, .forceLogout, .cpuPatch, .feedbackPatch, .userPatch]
        auditRows = (1...30).map { n in
            let target = users[(n * 5) % Self.userCount]
            return AdminAuditRow(id: n, createdAt: Self.iso(now.addingTimeInterval(-Double(n) * 11_000)), action: actions[n % actions.count],
                                 admin: AdminActor(id: Self.userID(1), username: "ian", email: "ian@example.com"),
                                 target: n % 4 == 0 ? nil : AdminActor(id: target.id, username: target.username, email: target.email),
                                 detail: .object(["note": .string("seeded"), "n": .number(Double(n))]))
        }.sorted { $0.createdAt > $1.createdAt }
        nextAuditID = 31
    }

    private func audit(adminID: String, targetID: String?, action: AdminAuditAction, detail: JSONValue?) {
        let admin = users.first { $0.id == adminID }
        let target = targetID.flatMap { id in users.first { $0.id == id } }
        auditRows.insert(AdminAuditRow(id: nextAuditID, createdAt: Self.iso(now), action: action,
                                       admin: AdminActor(id: adminID, username: admin?.username, email: admin?.email),
                                       target: targetID.map { AdminActor(id: $0, username: target?.username, email: target?.email) },
                                       detail: detail), at: 0)
        nextAuditID += 1
    }

    private func row(for user: AdminUserDetail) -> AdminUserRow {
        AdminUserRow(id: user.id, email: user.email, username: user.username, firstName: user.firstName, lastName: user.lastName,
                     appRole: user.appRole, isActive: user.isActive, createdAt: user.createdAt, lastLoginAt: user.lastLoginAt,
                     gamesPlayed: gamesPlayed[user.id] ?? 0, sessionVersion: user.sessionVersion, oauthProvider: user.oauthProvider)
    }

    /// A legal game played by two random CPUs with the row's seats, up to `moves_played`
    /// for an unfinished game or the whole board for a finished one.
    static func simulatedReplay(for game: AdminGameRow) -> GameReplayPayload {
        let players = game.participants.enumerated().map { index, seat in
            PlayerState(id: index + 1, name: seat.displayName, colorHex: seat.color)
        }
        var sim = Game(boardSize: game.boardSize, players: players)
        var rng = SplitMix64(seed: UInt64(game.id))
        let limit = game.endTime == nil ? game.boardSize * game.boardSize / 3 : Int.max
        var turns: [ReplayTurn] = []
        while !sim.isOver, turns.count < limit {
            let cell = CPUStrategy.random.chooseMove(in: sim, using: &rng)
            let slot = sim.currentPlayer.id
            guard (try? sim.place(at: cell)) != nil else { break }
            turns.append(ReplayTurn(turnNumber: turns.count + 1, boardSlotId: slot, rowIndex: cell.row, colIndex: cell.col))
        }
        let participants = game.participants.enumerated().map { index, seat in
            ReplayParticipant(participantId: seat.participantId, boardSlotId: index + 1, displayName: seat.displayName, color: seat.color,
                              participantType: seat.participantType.rawValue, cpuType: seat.cpuType)
        }
        return GameReplayPayload(gameId: game.id, boardSize: game.boardSize, timer: game.timer, gameType: game.type,
                                 participants: participants, turns: turns)
    }

    // MARK: Helpers

    private static func slice<T>(_ rows: [T], _ page: PageRequest) -> [T] {
        guard page.offset < rows.count else { return [] }
        return Array(rows[page.offset..<min(rows.count, page.offset + page.limit)])
    }

    private static func notFound(_ detail: String) -> APIError {
        .http(status: 404, body: #"{"detail":"\#(detail)"}"#)
    }

    /// Offset timestamp, like the server's timestamptz columns.
    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date).replacingOccurrences(of: "Z", with: "+00:00")
    }

    /// Naive UTC, like `games.games.*` and `auth.users.created_at`.
    static func naive(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return String(formatter.string(from: date).dropLast())
    }

    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
