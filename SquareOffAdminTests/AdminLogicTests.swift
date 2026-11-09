import Foundation
import SquareOffNet
import Testing
@testable import SquareOffAdmin

struct OverviewMetricsTests {
    private func point(_ day: String, local: Int = 1, online: Int = 1, cpu: Int = 1, completed: Int = 2, users: Int = 0, guests: Int = 0) -> AdminTimeseriesPoint {
        try! JSONDecoder().decode(AdminTimeseriesPoint.self, from: Data("""
        {"date":"\(day)","games_started":{"local":\(local),"online":\(online),"cpu":\(cpu)},"games_completed":\(completed),"new_users":\(users),"new_guest_sessions":\(guests)}
        """.utf8))
    }

    @Test func totalsAndWindows() {
        let series = (1...60).map { point(String(format: "2026-09-%02d", $0 % 30 + 1), local: $0, completed: $0 / 2) }
        let windows = OverviewMetrics.splitWindows(series)
        #expect(windows.current.count == 30 && windows.previous.count == 30)
        #expect(windows.previous.first == series.first && windows.current.last == series.last)
        let totals = OverviewMetrics.totals(windows.current)
        #expect(totals.local == (31...60).reduce(0, +) && totals.started == totals.local + 60)
        #expect(OverviewMetrics.totals([]).completionRate == nil)
        #expect(OverviewMetrics.totals([point("d", local: 8, online: 0, cpu: 0, completed: 5)]).completionRate == 62.5)
        // Fewer than two windows: the previous window is whatever is left.
        let short = OverviewMetrics.splitWindows(Array(series.prefix(40)))
        #expect(short.current.count == 30 && short.previous.count == 10)
    }

    @Test func trends() {
        #expect(OverviewMetrics.percentTrend(current: 90, previous: 70) == .init(direction: .up, label: "+28.6%"))
        #expect(OverviewMetrics.percentTrend(current: 48, previous: 50) == .init(direction: .down, label: "-4%"))
        #expect(OverviewMetrics.percentTrend(current: 5, previous: 5) == .init(direction: .neutral, label: "0%"))
        #expect(OverviewMetrics.percentTrend(current: 5, previous: 0) == nil)
        #expect(OverviewMetrics.pointTrend(current: 63.6, previous: 62.4) == .init(direction: .up, label: "+1.2 pt"))
        #expect(OverviewMetrics.pointTrend(current: 50, previous: nil) == nil)
    }
}

struct AdminFormattingTests {
    @Test func naiveTimestampsAreUTC() throws {
        let naive = try #require(ServerDate.parse("2025-10-18T12:00:00"))
        let aware = try #require(ServerDate.parse("2025-10-18T12:00:00+00:00"))
        let fractional = try #require(ServerDate.parse("2025-10-18T12:00:00.412771+00:00"))
        #expect(naive == aware)
        #expect(abs(fractional.timeIntervalSince(aware) - 0.412771) < 0.001)
        #expect(ServerDate.parse("2025-10-18T14:00:00+02:00") == aware)
        #expect(ServerDate.parse(nil) == nil && ServerDate.parse("nope") == nil)
        #expect(ServerDate.shortDay("2025-10-18").contains("18"))
    }

    @Test func durationsAndRelativeTimes() {
        #expect(AdminFormat.duration(400) == "6 min 40 s")
        #expect(AdminFormat.duration(42) == "42 s")
        #expect(AdminFormat.duration(3600) == "1 h")
        #expect(AdminFormat.duration(3780) == "1 h 3 min")
        #expect(AdminFormat.duration(nil) == "—")
        let now = Date()
        #expect(AdminFormat.relative(MockAdminAPITime.iso(now.addingTimeInterval(-10)), now: now) == "just now")
        #expect(AdminFormat.relative(MockAdminAPITime.iso(now.addingTimeInterval(-300)), now: now) == "5 min ago")
        #expect(AdminFormat.relative(MockAdminAPITime.iso(now.addingTimeInterval(-7200)), now: now) == "2 h ago")
        #expect(AdminFormat.relative(nil, now: now) == "—")
        #expect(AdminFormat.percent(37.5) == "37.5%" && AdminFormat.percent(nil) == "—")
    }
}

enum MockAdminAPITime {
    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

@MainActor
struct AdminQueryTests {
    @Test func keepsDataThroughAFailedRefresh() async {
        let flag = Flag()
        let query = AdminQuery<Int> {
            if await flag.shouldFail { throw APIError.http(status: 500, body: #"{"detail":"boom"}"#) }
            return 42
        }
        #expect(query.status == .idle && query.value == nil)
        await query.refresh()
        #expect(query.value == 42 && query.status == .idle && query.error == nil)
        await flag.set(true)
        await query.refresh()
        #expect(query.value == 42 && query.status == .failed && query.error == "boom")
    }

    @Test func aStaleAnswerNeverOverwritesANewerOne() async {
        let counter = Counter()
        let query = AdminQuery<Int> {
            let n = await counter.next()
            if n == 1 { try await Task.sleep(for: .milliseconds(200)) }   // the first call is slow
            return n
        }
        async let first: () = query.refresh()
        try? await Task.sleep(for: .milliseconds(20))
        await query.refresh()
        await first
        #expect(query.value == 2)
    }

    @Test func pagedQueryResetsThePageOnANewFilter() async {
        let list = PagedQuery<Int, String>(query: "a") { query, page in
            let all = Array(0..<120)
            let slice = Array(all[page.offset..<min(all.count, page.offset + page.limit)])
            return (query == "none" ? 0 : all.count, query == "none" ? [] : slice)
        }
        await list.load()
        #expect(list.total == 120 && list.pages == 3 && list.items.first == 0 && list.rangeLabel == "1–50 of 120")
        await list.goTo(page: 2)
        #expect(list.page == 2 && list.items == Array(100..<120) && list.rangeLabel == "101–120 of 120")
        await list.setQuery("b")
        #expect(list.page == 0 && list.items.first == 0)
        await list.setQuery("none")
        #expect(list.isEmpty && list.rangeLabel == "0 of 0")
    }

    @Test func errorsBecomeShortCopy() {
        #expect(AdminErrors.message(for: APIError.http(status: 429, body: "{}")) == "Too many admin requests. Try again in a few minutes.")
        #expect(AdminErrors.message(for: APIError.http(status: 403, body: #"{"detail":"SuperAdmin access required"}"#)) == "This account is no longer an admin.")
        #expect(AdminErrors.message(for: APIError.http(status: 404, body: #"{"detail":"User not found"}"#)) == "User not found")
        #expect(AdminErrors.message(for: APIError.http(status: 500, body: "<html>")) == "The server answered HTTP 500.")
        #expect(AdminErrors.message(for: APIError.timeout) == "The server didn't answer in time.")
    }
}

private actor Flag {
    var shouldFail = false
    func set(_ value: Bool) { shouldFail = value }
}

private actor Counter {
    var value = 0
    func next() -> Int { value += 1; return value }
}
