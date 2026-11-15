import Foundation
import Testing
import SquareOffCore
@testable import SquareOffNet

private func adminFixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/admin"))
    return try Data(contentsOf: url)
}

private func decodeAdmin<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
    try JSONDecoder().decode(type, from: adminFixture(name))
}

private func jsonObject(_ value: some Encodable) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
}

/// The `/api/admin/*` shapes (`hero-client/src/services/adminAPI.ts`), including the values a
/// screen must survive: unknown enum values, nulls, naive and offset timestamps.
@Suite("Admin API decoding")
struct AdminDecodingTests {
    @Test func healthAndLive() throws {
        let health = try decodeAdmin(AdminHealth.self, "health")
        #expect(health.db.pool?.inUse == 1 && health.model.move?.col == 4 && health.app.buildSha == "17f5c51")
        let live = try decodeAdmin(AdminLiveSnapshot.self, "live")
        #expect(live.rooms.first?.phase == .playing)
        #expect(live.rooms.first?.players.last?.isCPU == true)
        #expect(live.rooms.last?.phase == .unknown)   // a phase this build doesn't know
        #expect(live.matchQueue.items.first?.ticketId == "t-6f3a")
        #expect(live.openRooms.first?.heartbeatAgeS == 4.2)
    }

    @Test func timeseries() throws {
        let series = try decodeAdmin(AdminTimeseries.self, "timeseries")
        #expect(series.series.count == 2 && series.series[0].gamesStarted.total == 12)
        #expect(series.totals.medianDurationMinOnline == nil && series.totals.providerMix.count == 2)
    }

    @Test func usersGamesAuditFeedbackCpus() throws {
        let users = try decodeAdmin(Paged<AdminUserRow>.self, "users_page")
        #expect(users.total == 42 && users.items[1].oauthProvider == "google" && users.items[1].appRole == .standard)
        let overview = try decodeAdmin(AdminUserOverview.self, "user_overview")
        #expect(overview.stats?.gamesWon == 7 && overview.identities.first?.provider == "google" && overview.user.displayName == "Pat")
        let userGames = try decodeAdmin(Paged<AdminUserGameRow>.self, "user_games")
        #expect(userGames.items.first?.result == .unfinished)
        let games = try decodeAdmin(Paged<AdminGameRow>.self, "games_page")
        #expect(games.items[0].winnerType == .user && games.items[0].participants.count == 2)
        #expect(games.items[0].scores?["1"] == .number(36))
        #expect(games.items[1].durationSec == nil && games.items[1].participants.isEmpty)
        let audit = try decodeAdmin(Paged<AdminAuditRow>.self, "audit_page")
        #expect(audit.items[0].action == .userPatch && audit.items[0].detail?["is_active"] == .bool(false))
        let feedback = try decodeAdmin(AdminFeedbackPage.self, "feedback_page")
        #expect(feedback.counts.handled == 4 && feedback.items[0].status == .new)
        let patched = try decodeAdmin(AdminFeedbackPatchResult.self, "patch_feedback")
        #expect(patched.item?.handledBy?.username == "ian")
        let cpus = try decodeAdmin(AdminItems<AdminCPURow>.self, "cpus")
        #expect(cpus.items.map(\.cpuType) == ["random", "cnn", "impossible"] && cpus.items[1].usageCount == 120)
        let stats = try decodeAdmin(AdminCPUStatsResponse.self, "cpus_stats")
        #expect(stats.items[0].humanWinRate == 37.5 && stats.items[0].usageByDay.count == 2)
        #expect(try decodeAdmin(AdminTestMove.self, "test_move").latencyMs == 38.2)
        #expect(try decodeAdmin(AdminForceLogoutResult.self, "force_logout").sessionVersion == 5)
    }

    @Test func unknownAuditActionsDecode() throws {
        let row = try JSONDecoder().decode(AdminAuditRow.self, from: Data(#"{"id":1,"created_at":"2026-01-01T00:00:00+00:00","action":"brand_new","admin":{"id":"a","username":null,"email":null},"target":null,"detail":null}"#.utf8))
        #expect(row.action == .unknown && row.admin.label == "a")
    }
}

@Suite("Admin API encoding")
struct AdminEncodingTests {
    @Test func queryItemsSkipNils() {
        let users = AdminUserQuery(q: "  pat ", sort: .gamesPlayed, dir: .asc, active: false, page: .page(2))
        let items = Dictionary(uniqueKeysWithValues: users.queryItems.map { ($0.name, $0.value ?? "") })
        #expect(items == ["q": "pat", "sort": "games_played", "dir": "asc", "active": "false", "limit": "50", "offset": "100"])
        let games = AdminGameQuery(type: .online, from: "2026-10-01", to: "2026-10-26", winner: .draw, minDuration: 60)
        let names = games.queryItems.map(\.name)
        #expect(names == ["type", "from", "to", "winner", "min_duration", "sort", "dir", "limit", "offset"])
        #expect(AdminAuditQuery().queryItems.map(\.name) == ["limit", "offset"])
    }

    @Test func patchesEncodeOnlyWhatIsSet() throws {
        #expect(Set(try jsonObject(AdminUserPatch(isActive: false)).keys) == ["is_active"])
        #expect(Set(try jsonObject(AdminCPUPatch(displayName: "X")).keys) == ["display_name"])
        let clearing = try jsonObject(AdminFeedbackPatch(status: .handled, clearNotes: true))
        #expect(clearing["status"] as? String == "handled" && clearing["notes"] is NSNull)
        #expect(Set(try jsonObject(AdminFeedbackPatch(notes: "Fixed")).keys) == ["notes"])
    }
}

@Suite("Mock admin API")
struct MockAdminAPITests {
    private func signedIn(role: String) async throws -> (MockSquareOffAPI, MockAdminAPI) {
        let accounts = MockSquareOffAPI(latency: .zero, demoRole: role)
        _ = try await accounts.login(LoginRequest(emailOrUsername: MockSquareOffAPI.demoUsername, password: MockSquareOffAPI.demoPassword))
        return (accounts, MockAdminAPI(accounts: accounts, latency: .zero))
    }

    @Test func standardUsersAreForbidden() async throws {
        let (_, admin) = try await signedIn(role: "standard")
        await #expect(throws: APIError.http(status: 403, body: #"{"detail":"SuperAdmin access required"}"#)) { _ = try await admin.live() }
        let anonymous = MockAdminAPI(accounts: MockSquareOffAPI(latency: .zero), latency: .zero)
        await #expect(throws: APIError.self) { _ = try await anonymous.cpus() }
    }

    @Test func listsPageFilterAndSort() async throws {
        let (_, admin) = try await signedIn(role: "superadmin")
        let all = try await admin.users(AdminUserQuery())
        #expect(all.total == MockAdminAPI.userCount + 1 && all.items.count == MockAdminAPI.userCount + 1)
        let inactive = try await admin.users(AdminUserQuery(active: false))
        #expect(inactive.items.allSatisfy { !$0.isActive } && inactive.total == 1)
        let byName = try await admin.users(AdminUserQuery(sort: .username, dir: .asc, page: PageRequest(limit: 5, offset: 0)))
        #expect(byName.items.count == 5 && byName.items.map(\.username) == byName.items.map(\.username).sorted())
        let search = try await admin.users(AdminUserQuery(q: "pat"))
        #expect(search.items.allSatisfy { $0.username.contains("pat") || $0.email.contains("pat") })
        let games = try await admin.games(AdminGameQuery(winner: .unfinished))
        #expect(games.items.allSatisfy { $0.endTime == nil })
        let page2 = try await admin.games(AdminGameQuery(page: .page(2)))
        #expect(page2.items.count == MockAdminAPI.gameCount - 100)
    }

    @Test func writesAreReflectedAndAudited() async throws {
        let (_, admin) = try await signedIn(role: "superadmin")
        let target = MockAdminAPI.userID(5)
        _ = try await admin.patchUser(id: target, AdminUserPatch(isActive: false, firstName: "Sam"))
        let overview = try await admin.userOverview(id: target)
        #expect(!overview.user.isActive && overview.user.firstName == "Sam" && overview.user.sessionVersion == 1)
        let audit = try await admin.userAudit(id: target, page: PageRequest())
        #expect(audit.items.first?.action == .userPatch && audit.items.first?.detail?["session_version_bumped"] == .bool(true))
        let logout = try await admin.forceLogout(id: target)
        #expect(logout.sessionVersion == 2)
        // Self-protection: the signed-in admin can't demote or sign out itself.
        await #expect(throws: APIError.self) { _ = try await admin.patchUser(id: MockSquareOffAPI.demoUserID, AdminUserPatch(isActive: false)) }
        await #expect(throws: APIError.self) { _ = try await admin.forceLogout(id: MockSquareOffAPI.demoUserID) }
    }

    @Test func feedbackAndCpus() async throws {
        let (_, admin) = try await signedIn(role: "superadmin")
        let before = try await admin.feedback(status: .new, page: PageRequest())
        let first = try #require(before.items.first)
        let result = try await admin.patchFeedback(id: first.id, AdminFeedbackPatch(status: .handled, notes: "Done"))
        #expect(result.item?.status == .handled && result.item?.notes == "Done" && result.item?.handledBy?.username == "demo")
        let after = try await admin.feedback(status: .new, page: PageRequest())
        #expect(after.counts.new == before.counts.new - 1)
        let cpus = try await admin.cpus()
        let unused = try #require(cpus.first { $0.usageCount == 0 })
        let used = try #require(cpus.first { $0.usageCount > 0 })
        await #expect(throws: APIError.http(status: 409, body: #"{"detail":"CPU has games in history and cannot be deleted"}"#)) { _ = try await admin.deleteCPU(id: used.id) }
        _ = try await admin.deleteCPU(id: unused.id)
        #expect(try await admin.cpus().count == cpus.count - 1)
        let move = try await admin.testMove(cpuType: "max-min", boardSize: 8)
        #expect((0..<8).contains(move.row) && (0..<8).contains(move.col))
    }

    @Test func replaysReplayLegally() async throws {
        let (_, admin) = try await signedIn(role: "superadmin")
        let games = try await admin.games(AdminGameQuery(page: PageRequest(limit: 12, offset: 0)))
        for row in games.items {
            let payload = try await admin.replay(gameID: row.id)
            var game = Game(boardSize: payload.boardSize, players: payload.participants.map { PlayerState(id: $0.boardSlotId, name: $0.displayName, colorHex: $0.color) })
            for turn in payload.turns { _ = try game.place(at: turn.cell) }
            #expect(row.endTime == nil ? !game.isOver : game.isOver)
        }
    }
}

/// The 2026-11-05 console additions: verified / suspect users, bulk deactivation, the engine
/// probe, `bulk_deactivate` audit rows and the test-move options.
@Suite("Admin API 2026-11 additions")
struct AdminParityTests {
    @Test func verifiedAndSuspectUsersDecode() throws {
        let page = try decodeAdmin(Paged<AdminUserRow>.self, "users_verified")
        #expect(page.items[0].isEmailVerified && !page.items[0].isSuspect)
        #expect(page.items[1].isSuspect && page.items[1].emailVerifiedAt == nil && page.items[1].gamesPlayed == 0)
        let old = try decodeAdmin(Paged<AdminUserRow>.self, "users_page")
        #expect(old.items[0].isSuspect == false && old.items[0].emailVerifiedAt == nil, "older servers: tolerated")
        #expect(try decodeAdmin(AdminUserOverview.self, "user_overview").user.emailVerifiedAt != nil)
    }

    @Test func healthWithAndWithoutTheEngine() throws {
        #expect(try decodeAdmin(AdminHealth.self, "health").engine == nil)
        let health = try decodeAdmin(AdminHealth.self, "health_engine")
        #expect(health.engine?.ok == true && health.engine?.version == "0.1.0" && health.engine?.move?.col == 4)
    }

    @Test func bulkDeactivationShapes() throws {
        #expect(try decodeAdmin(AdminBulkDeactivateResult.self, "bulk_deactivate").batchId == "3f9a1c2b4d5e")
        let audit = try decodeAdmin(Paged<AdminAuditRow>.self, "audit_bulk")
        #expect(audit.items.allSatisfy { $0.action == .bulkDeactivate })
        #expect(audit.items[0].detail?["source"] == .string("suspect") && audit.items[0].detail?["reason"] == .null)
        #expect(audit.items[1].detail?["reason"]?.stringValue == "signup bots" && audit.items[1].detail?["session_version"]?.stringValue == "2")
        #expect(try jsonObject(BulkDeactivateRequest.ids(["a", "b"], reason: "x")).keys.sorted() == ["reason", "user_ids"])
        let suspects = try jsonObject(BulkDeactivateRequest.suspects())
        #expect(suspects.keys.sorted() == ["filter"] && suspects["filter"] as? String == "suspect")
        #expect(AdminAuditAction.allCases.contains(.bulkDeactivate))
    }

    @Test func queryPatchAndTestMoveEncoding() throws {
        let items = Dictionary(uniqueKeysWithValues: AdminUserQuery(verified: false, suspect: true).queryItems.map { ($0.name, $0.value ?? "") })
        #expect(items["verified"] == "false" && items["suspect"] == "true")
        #expect(AdminUserQuery(suspect: true).hasFilters)
        #expect(try jsonObject(AdminUserPatch(emailVerified: true)).keys.sorted() == ["email_verified"])
        #expect(!AdminUserPatch(emailVerified: false).isEmpty)
        #expect(try jsonObject(AdminTestMoveRequest(boardSize: 10, deadlineMs: 500)).keys.sorted() == ["board_size", "deadline_ms"])
        #expect(try jsonObject(AdminTestMoveRequest()).isEmpty)
        let move = try decodeAdmin(AdminTestMove.self, "test_move_engine")
        #expect(move.engine?.mode == "ab" && move.engine?.deadlineMs == 1500 && move.latencyMs == 212.4)
        #expect(try decodeAdmin(AdminTestMove.self, "test_move").engine == nil)
    }
}

@Suite("Mock admin API 2026-11 behaviour")
struct MockAdminParityTests {
    private func api() -> MockAdminAPI { MockAdminAPI(accounts: nil, latency: .zero) }

    @Test func suspectRule() {
        #expect(MockAdminAPI.looksSuspect(username: "qXbLmRtWcPaZ"))
        #expect(!MockAdminAPI.looksSuspect(username: "ian"))
        #expect(!MockAdminAPI.looksSuspect(username: "Abcdefghijkl"), "one case flip")
        #expect(!MockAdminAPI.looksSuspect(username: "qXbLmRtWcPaZ123"), "digits")
    }

    @Test func suspectsAreSeededFilteredAndBulkDeactivated() async throws {
        let api = api()
        let suspects = try await api.users(AdminUserQuery(suspect: true))
        #expect(suspects.total == 3 && suspects.items.allSatisfy { $0.isSuspect && !$0.isEmailVerified && $0.gamesPlayed == 0 })
        let unverified = try await api.users(AdminUserQuery(verified: false))
        #expect(unverified.total > suspects.total)
        let first = try await api.bulkDeactivate(.suspects(reason: "wave"))
        #expect(first.deactivated == 3 && first.skipped == 0 && first.batchId != nil)
        let audit = try await api.userAudit(id: suspects.items[0].id, page: PageRequest())
        #expect(audit.items.first?.action == .bulkDeactivate && audit.items.first?.detail?["batch_id"]?.stringValue == first.batchId)
        #expect(try await api.users(AdminUserQuery(active: false)).total == 4)   // user 8 was already inactive
        let again = try await api.bulkDeactivate(.suspects())
        #expect(again.deactivated == 0 && again.batchId == nil)
        // Selected ids: the caller (user 1, superadmin) and an inactive user are skipped.
        let mixed = try await api.bulkDeactivate(.ids([MockAdminAPI.userID(1), MockAdminAPI.userID(8), MockAdminAPI.userID(5)]))
        #expect(mixed.deactivated == 1 && mixed.skipped == 2)
        await #expect(throws: APIError.self) { _ = try await api.bulkDeactivate(.ids([])) }
    }

    @Test func emailVerifiedPatchRoundTrips() async throws {
        let api = api()
        let target = try await api.users(AdminUserQuery(verified: false, suspect: false)).items[0].id
        _ = try await api.patchUser(id: target, AdminUserPatch(emailVerified: true))
        #expect(try await api.userOverview(id: target).user.emailVerifiedAt != nil)
        _ = try await api.patchUser(id: target, AdminUserPatch(emailVerified: false))
        #expect(try await api.userOverview(id: target).user.emailVerifiedAt == nil)
    }

    @Test func engineHealthCpuRowsAndTestMoveRules() async throws {
        let api = api()
        #expect(try await api.health(refresh: false).engine?.ok == true)
        let cpus = try await api.cpus()
        #expect(cpus.count == CPULevel.selectable.count + 1 && cpus.contains { $0.cpuType == "cnn" })
        await #expect(throws: APIError.self) { _ = try await api.testMove(cpuType: "grandmaster", boardSize: 4, deadlineMs: nil) }
        await #expect(throws: APIError.self) { _ = try await api.testMove(cpuType: "grandmaster", boardSize: 8, deadlineMs: 10) }
        let engine = try await api.testMove(cpuType: "impossible", boardSize: 8, deadlineMs: 250)
        #expect(engine.engine?.mode == "nn-puct" && engine.engine?.deadlineMs == 250)
        let heuristic = try await api.testMove(cpuType: "random", boardSize: 20)
        #expect(heuristic.engine == nil && (0..<20).contains(heuristic.row))
        #expect(try await api.games(AdminGameQuery(cpuType: "cnn")).total > 0, "retired CNN games stay filterable")
    }
}
