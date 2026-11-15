import Charts
import SquareOffNet
import SwiftUI

/// Health, the six KPI tiles (last 30 days vs the 30 before), activity, trends and a live
/// summary (web `pages/admin/overview.tsx`).
struct OverviewView: View {
    @Environment(AppModel.self) private var app
    @Environment(AdminAppModel.self) private var console
    @State private var health: AdminQuery<AdminHealth>?
    @State private var series: AdminQuery<AdminTimeseries>?
    @State private var live: AdminQuery<AdminLiveSnapshot>?
    @State private var reprobing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeading(title: "Overview", description: "How the service and the game are doing, the last 30 days against the 30 before.")
                if let health { healthStrip(health) }
                if let series { metrics(series) }
                if let live { liveSummary(live) }
            }
            .padding(16)
            .frame(maxWidth: 960)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("Overview")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await refreshAll() }
        .onAppear {
            if health == nil {
                let api = app.admin
                health = AdminQuery { try await api.health(refresh: false) }
                series = AdminQuery { try await api.timeseries(days: 2 * OverviewMetrics.windowDays, tz: TimeZone.current.identifier) }
                live = AdminQuery { try await api.live() }
            }
        }
        .task { await health?.refresh(); await series?.refresh() }
        .adminPolling(every: .seconds(15)) { await live?.refresh() }
    }

    private func refreshAll() async {
        async let a: () = health?.refresh() ?? ()
        async let b: () = series?.refresh() ?? ()
        async let c: () = live?.refresh() ?? ()
        _ = await (a, b, c)
    }

    // MARK: Health

    private func healthStrip(_ query: AdminQuery<AdminHealth>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel("Health")
                Spacer()
                Button {
                    reprobing = true
                    Task {
                        let api = app.admin
                        let probe = AdminQuery { try await api.health(refresh: true) }
                        await probe.refresh()
                        await query.refresh()
                        reprobing = false
                    }
                } label: { PendingLabel(title: "Re-probe", pendingTitle: "Probing…", symbol: "arrow.clockwise", isPending: reprobing) }
                    .buttonStyle(SecondaryButtonStyle(small: true, fullWidth: false))
                    .disabled(reprobing)
            }
            if let error = query.error, query.value == nil {
                SectionError(message: error) { Task { await query.refresh() } }
            } else if let h = query.value {
                let columns = [GridItem(.adaptive(minimum: 150), spacing: 10)]
                LazyVGrid(columns: columns, spacing: 10) {
                    healthTile("Database", ok: h.db.ok, detail: h.db.ok ? "\(h.db.latencyMs.map { String(format: "%.0f ms", $0) } ?? "—") · pool \(h.db.pool?.inUse ?? 0)/\(h.db.pool?.max ?? 0)" : (h.db.error ?? "down"))
                    healthTile("Model", ok: h.model.ok, detail: h.model.ok ? "\(h.model.latencyMs.map { String(format: "%.0f ms", $0) } ?? "—")\(h.model.cached ? " · cached" : "")" : (h.model.error ?? "down"))
                    healthTile("Mail", ok: h.mail.configured, detail: h.mail.server ?? "not configured")
                    healthTile("App", ok: true, detail: "\(h.app.version) · \(h.app.buildSha.map { String($0.prefix(7)) } ?? "no sha") · up \(AdminFormat.duration(h.app.uptimeS))")
                }
            } else {
                SkeletonRows(count: 2)
            }
        }
        .padding(16)
        .card()
    }

    private func healthTile(_ title: String, ok: Bool, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(ok ? Theme.success : Theme.dangerText).frame(width: 8, height: 8)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.foreground)
            }
            Text(detail).font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Metrics

    @ViewBuilder
    private func metrics(_ query: AdminQuery<AdminTimeseries>) -> some View {
        if let error = query.error, query.value == nil {
            SectionError(message: error) { Task { await query.refresh() } }
        } else if let data = query.value {
            let windows = OverviewMetrics.splitWindows(data.series)
            let current = OverviewMetrics.totals(windows.current)
            let previous = OverviewMetrics.totals(windows.previous)
            let columns = [GridItem(.adaptive(minimum: 150), spacing: 10)]
            LazyVGrid(columns: columns, spacing: 10) {
                kpi("Registered users", AdminFormat.count(data.totals.registeredUsers), nil)
                kpi("Games started", AdminFormat.count(current.started), OverviewMetrics.percentTrend(current: current.started, previous: previous.started))
                kpi("Games completed", AdminFormat.count(current.completed), OverviewMetrics.percentTrend(current: current.completed, previous: previous.completed))
                kpi("New users", AdminFormat.count(current.newUsers), OverviewMetrics.percentTrend(current: current.newUsers, previous: previous.newUsers))
                kpi("Guest sessions", AdminFormat.count(current.guestSessions), OverviewMetrics.percentTrend(current: current.guestSessions, previous: previous.guestSessions))
                kpi("Completion rate", AdminFormat.percent(current.completionRate), OverviewMetrics.pointTrend(current: current.completionRate, previous: previous.completionRate))
            }
            HStack(spacing: 10) {
                Stat(label: "DAU", value: AdminFormat.count(data.totals.dau)).frame(maxWidth: .infinity, alignment: .leading)
                Stat(label: "WAU", value: AdminFormat.count(data.totals.wau)).frame(maxWidth: .infinity, alignment: .leading)
                Stat(label: "MAU", value: AdminFormat.count(data.totals.mau)).frame(maxWidth: .infinity, alignment: .leading)
                Stat(label: "Median game", value: data.totals.medianDurationMin.map { String(format: "%.1f min", $0) } ?? "—").frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .card()
            chartCard("Games started", "Per day, by kind, last \(windows.current.count) days") {
                Chart {
                    ForEach(windows.current) { point in
                        BarMark(x: .value("Day", point.date), y: .value("Local", point.gamesStarted.local)).foregroundStyle(by: .value("Kind", "Local"))
                        BarMark(x: .value("Day", point.date), y: .value("Online", point.gamesStarted.online)).foregroundStyle(by: .value("Kind", "Online"))
                        BarMark(x: .value("Day", point.date), y: .value("CPU", point.gamesStarted.cpu)).foregroundStyle(by: .value("Kind", "CPU"))
                    }
                }
                .chartForegroundStyleScale(["Local": Theme.link, "Online": Theme.success, "CPU": Theme.warning])
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { value in AxisValueLabel { if let day = value.as(String.self) { Text(ServerDate.shortDay(day)) } } } }
            }
            chartCard("New users and guest sessions", "Per day") {
                Chart {
                    ForEach(windows.current) { point in
                        LineMark(x: .value("Day", point.date), y: .value("New users", point.newUsers)).foregroundStyle(by: .value("Series", "New users"))
                        LineMark(x: .value("Day", point.date), y: .value("Guest sessions", point.newGuestSessions)).foregroundStyle(by: .value("Series", "Guest sessions"))
                    }
                    .interpolationMethod(.monotone)
                }
                .chartForegroundStyleScale(["New users": Theme.link, "Guest sessions": Theme.warning])
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { value in AxisValueLabel { if let day = value.as(String.self) { Text(ServerDate.shortDay(day)) } } } }
            }
            HStack(alignment: .top, spacing: 10) {
                mixCard("Sign-in methods", data.totals.providerMix.map { ($0.provider, $0.count) })
                mixCard("Seats", [("Users", data.totals.guestVsRegisteredParticipants.user), ("Guests", data.totals.guestVsRegisteredParticipants.guest), ("CPU", data.totals.guestVsRegisteredParticipants.cpu)])
            }
        } else {
            SkeletonRows(count: 6).padding(16).card()
        }
    }

    private func kpi(_ label: String, _ value: String, _ trend: OverviewMetrics.Trend?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Stat(label: label, value: value, size: 22)
            if let trend {
                Chip(text: trend.label, style: trend.direction == .up ? .success : (trend.direction == .down ? .danger : .default),
                     symbol: trend.direction == .up ? "arrow.up.right" : (trend.direction == .down ? "arrow.down.right" : "minus"))
            } else {
                Text("vs previous 30 days: —").font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(fill: Theme.surfaceSecondary, radius: 12)
    }

    private func chartCard<Content: View>(_ title: String, _ subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Theme.display(15, relativeTo: .headline)).foregroundStyle(Theme.foreground)
            Text(subtitle).font(.caption).foregroundStyle(Theme.muted)
            content().frame(height: 200)
        }
        .padding(16)
        .card()
    }

    private func mixCard(_ title: String, _ parts: [(String, Int)]) -> some View {
        let total = max(1, parts.reduce(0) { $0 + $1.1 })
        let palette = [Theme.link, Theme.success, Theme.warning, Theme.dangerText, Theme.foregroundSecondary]
        return VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Theme.display(15, relativeTo: .headline)).foregroundStyle(Theme.foreground)
            Chart(Array(parts.enumerated()), id: \.offset) { index, part in
                SectorMark(angle: .value(part.0, part.1), innerRadius: .ratio(0.68), angularInset: 1.5)
                    .cornerRadius(6)
                    .foregroundStyle(palette[index % palette.count])
            }
            .chartLegend(.hidden)
            .frame(height: 120)
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                HStack(spacing: 8) {
                    Circle().fill(palette[index % palette.count]).frame(width: 8, height: 8)
                    Text(part.0).font(.caption).foregroundStyle(Theme.foregroundSecondary)
                    Spacer()
                    Text("\(part.1) · \(part.1 * 100 / total)%").font(.caption).monospacedDigit().foregroundStyle(Theme.foreground)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: Live summary

    @ViewBuilder
    private func liveSummary(_ query: AdminQuery<AdminLiveSnapshot>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Live now")
                Spacer()
                UpdatedAgo(date: query.updatedAt)
            }
            if let snapshot = query.value {
                let playing = snapshot.rooms.filter { $0.phase == .playing }.count
                HStack(spacing: 10) {
                    Stat(label: "Rooms", value: "\(snapshot.rooms.count)").frame(maxWidth: .infinity, alignment: .leading)
                    Stat(label: "Playing", value: "\(playing)", tone: playing > 0 ? .success : .default).frame(maxWidth: .infinity, alignment: .leading)
                    Stat(label: "Sockets", value: "\(snapshot.websocket.connections)").frame(maxWidth: .infinity, alignment: .leading)
                    Stat(label: "In queue", value: "\(snapshot.matchQueue.tickets)", tone: snapshot.matchQueue.tickets > 0 ? .warning : .default).frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("Open Live") { console.section = .live }.buttonStyle(TertiaryButtonStyle(small: true, fullWidth: false))
            } else if let error = query.error {
                Text(error).font(.caption).foregroundStyle(Theme.dangerText)
            } else {
                SkeletonRows(count: 1)
            }
        }
        .padding(16)
        .card()
    }
}
