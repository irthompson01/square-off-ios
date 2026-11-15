import Charts
import SquareOffNet
import SwiftUI

/// Game stats (web `/profile/stats`): the Statistics panel (All / Humans / CPU with a win-rate
/// donut, tiles and filters) and the Game history panel (W/L/T strip, rows, server paging, replays).
struct StatsView: View {
    @Environment(AppModel.self) private var app

    enum Scope: String, CaseIterable, Identifiable {
        case all, humans, cpu
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "All"
            case .humans: "Humans"
            case .cpu: "CPU"
            }
        }
        var symbol: String {
            switch self {
            case .all: "globe"
            case .humans: "trophy"
            case .cpu: "chart.bar"
            }
        }
    }

    static let pageSize = 10

    @State private var scope: Scope = .all
    @State private var all: PlayerStatsView?
    @State private var humans: PlayerStatsView?
    @State private var cpuRows: [PlayerStatsCPUView] = []
    @State private var humanFilters = ProfileStatsFilters(boardSizes: [], timers: [], cpuTypes: [])
    @State private var cpuFilters = ProfileStatsFilters(boardSizes: [], timers: [], cpuTypes: [])
    @State private var humanBoard: Int?
    @State private var humanTimer: Int?
    @State private var cpuBoard: Int?
    @State private var cpuTimer: Int?
    @State private var cpuType: String?
    @State private var history: RecentGamesPage?
    @State private var page = 0
    @State private var isLoading = true
    @State private var isPaging = false
    @State private var fatal: String?
    @State private var replayGame: ReplayTarget?

    struct ReplayTarget: Identifiable {
        let id: Int
        let opponent: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeading(title: "Game stats", description: "Your record across every game, by opponent type.")
                if isLoading {
                    skeleton
                } else if let fatal {
                    AlertBox(.danger, title: "Couldn't load your stats", message: fatal)
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            statisticsPanel.frame(maxWidth: .infinity)
                            historyPanel.frame(maxWidth: .infinity)
                        }
                        .frame(minWidth: 900)
                        VStack(spacing: 20) {
                            statisticsPanel
                            historyPanel
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 1152)
            .frame(maxWidth: .infinity)
        }
        .appBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: app.account) { await loadAll() }
        .task(id: "\(humanBoard ?? 0)-\(humanTimer ?? -1)") { await loadHumans() }
        .task(id: "\(cpuBoard ?? 0)-\(cpuTimer ?? -1)-\(cpuType ?? "")") { await loadCPU() }
        .task(id: page) { await loadHistory() }
        .sheet(item: $replayGame) { target in
            NavigationStack { ReplayView(gameID: target.id) }
                .presentationBackground(Theme.overlay)
        }
    }

    private var skeleton: some View {
        VStack(spacing: 16) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    SkeletonBar(width: 140, height: 18)
                    SkeletonBar(width: 220, height: 12)
                    SkeletonBar(height: 160)
                }
                .padding(20)
                .card()
            }
        }
    }

    // MARK: Statistics

    private var summary: StatsSummary? {
        switch scope {
        case .all: all.map(StatsSummary.init)
        case .humans: humans.map(StatsSummary.init)
        case .cpu: StatsSummary.combine(cpuRows)
        }
    }

    private var statisticsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Statistics").font(Theme.display(18, relativeTo: .headline)).foregroundStyle(Theme.foreground)
                Text("All games, human opponents, or CPU.").font(.subheadline).foregroundStyle(Theme.foregroundSecondary)
            }
            SegmentedPills(options: Scope.allCases, selection: $scope, title: \.title, symbol: \.symbol, compact: true)
            if scope == .humans { humanFilterRow }
            if scope == .cpu { cpuFilterRow }
            if scope == .cpu, cpuRows.isEmpty {
                cpuEmpty
            } else if let summary {
                StatsSummaryView(summary: summary)
            }
        }
        .padding(20)
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Statistics")
    }

    private var humanFilterRow: some View {
        HStack(spacing: 10) {
            filterMenu("Board", selection: $humanBoard, options: humanFilters.boardSizes, none: "All sizes") { "\($0) × \($0)" }
            filterMenu("Timer", selection: $humanTimer, options: humanFilters.timers, none: "Any timer") { $0 == 0 ? "No timer" : "\($0) seconds" }
        }
    }

    private var cpuFilterRow: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                filterMenu("Board", selection: Binding(get: { cpuBoard }, set: { cpuBoard = $0; cpuType = nil }), options: cpuFilters.boardSizes, none: "All sizes") { "\($0) × \($0)" }
                filterMenu("Timer", selection: Binding(get: { cpuTimer }, set: { cpuTimer = $0; cpuType = nil }), options: cpuFilters.timers, none: "Any timer") { $0 == 0 ? "No timer" : "\($0) seconds" }
            }
            filterMenu("CPU type", selection: $cpuType, options: cpuFilters.cpuTypes, none: "All", label: Self.cpuTypeLabel)
        }
    }

    private func filterMenu<Option: Hashable>(_ title: String, selection: Binding<Option?>, options: [Option], none: String,
                                              label: @escaping (Option) -> String) -> some View {
        Menu {
            Button {
                selection.wrappedValue = nil
            } label: {
                if selection.wrappedValue == nil { Label(none, systemImage: "checkmark") } else { Text(none) }
            }
            ForEach(options, id: \.self) { option in
                Button {
                    selection.wrappedValue = option
                } label: {
                    if selection.wrappedValue == option { Label(label(option), systemImage: "checkmark") } else { Text(label(option)) }
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.caption).foregroundStyle(Theme.muted)
                    Text(selection.wrappedValue.map(label) ?? none).font(.subheadline).foregroundStyle(Theme.foreground).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .frame(maxWidth: .infinity)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.fieldBorder))
        }
        .accessibilityLabel(title)
    }

    private var cpuFiltersActive: Bool { cpuBoard != nil || cpuTimer != nil || cpuType != nil }

    @ViewBuilder
    private var cpuEmpty: some View {
        if cpuFiltersActive {
            EmptyState(symbol: "line.3.horizontal.decrease.circle", title: "No CPU games match these filters", text: "Try a different board, timer or CPU type.") {
                Button("Clear filters") {
                    cpuBoard = nil
                    cpuTimer = nil
                    cpuType = nil
                }
                .buttonStyle(SecondaryButtonStyle(small: true, fullWidth: false))
            }
        } else {
            EmptyState(symbol: "cpu", title: "No CPU games yet", text: "Finished games against the computer show up here.") {
                Button("Play vs Computer") { app.pendingPlayRoute = .play }
                    .buttonStyle(SecondaryButtonStyle(small: true, fullWidth: false))
            }
        }
    }

    static func cpuTypeLabel(_ type: String) -> String {
        switch type {
        case "random": "Random"
        case "max_random", "max-random": "Max-Random"
        case "cnn": "CNN"
        case "max-min", "max_min": "Max-Min"
        case "max-min-optimal": "Max-Min-Optimal"
        case "max-min-io": "Max-Min-IO"
        default: type
        }
    }

    // MARK: History

    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Game history").font(Theme.display(18, relativeTo: .headline)).foregroundStyle(Theme.foreground)
                Text("Newest first, 10 per page.").font(.subheadline).foregroundStyle(Theme.foregroundSecondary)
            }
            if let history, history.total > 0 {
                resultStrip(history.games)
                VStack(spacing: 0) {
                    ForEach(history.games) { row in
                        historyRow(row)
                        Theme.separator.frame(height: 1)
                    }
                }
                .opacity(isPaging ? 0.6 : 1)
                pagination(total: history.total)
            } else {
                EmptyState(symbol: "gamecontroller", title: "No games yet", text: "Finished games appear here with their result and a replay.") {
                    Button("Play now") { app.pendingPlayRoute = .play }
                        .buttonStyle(SecondaryButtonStyle(small: true, fullWidth: false))
                }
            }
        }
        .padding(20)
        .card()
    }

    private func resultStrip(_ rows: [RecentGameRow]) -> some View {
        let columns = [GridItem(.adaptive(minimum: 24), spacing: 6)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(rows) { row in
                Text(row.result)
                    .font(Theme.display(11, relativeTo: .caption2))
                    .foregroundStyle(Self.resultColor(row.result))
                    .frame(width: 24, height: 24)
                    .background(Self.resultColor(row.result).opacity(0.16), in: Circle())
                    .accessibilityLabel(Self.resultWord(row.result))
            }
        }
    }

    private func historyRow(_ row: RecentGameRow) -> some View {
        HStack(spacing: 12) {
            Text(row.gameType.uppercased())
                .font(Theme.display(10, relativeTo: .caption2)).tracking(1).foregroundStyle(Theme.muted)
                .frame(width: 52, alignment: .leading)
            Text(row.opponentLabel).font(.subheadline).foregroundStyle(Theme.foreground).lineLimit(1)
            Spacer()
            Text("\(row.myScore)").font(Theme.display(14, relativeTo: .subheadline)).monospacedDigit().foregroundStyle(Theme.foreground)
            Chip(text: Self.resultWord(row.result), style: row.result == "W" ? .success : row.result == "L" ? .danger : .default)
            Button {
                replayGame = ReplayTarget(id: row.gameId, opponent: row.opponentLabel)
            } label: {
                Image(systemName: "play").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.foregroundSecondary).frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Replay game vs \(row.opponentLabel)")
        }
        .padding(.vertical, 10)
    }

    private func pagination(total: Int) -> some View {
        let pages = max(1, (total + Self.pageSize - 1) / Self.pageSize)
        let first = page * Self.pageSize + 1
        let last = min(total, (page + 1) * Self.pageSize)
        return VStack(alignment: .leading, spacing: 10) {
            Text("\(first)–\(last) of \(total)").font(.subheadline).foregroundStyle(Theme.foregroundSecondary)
            HStack(spacing: 4) {
                pageButton(symbol: "chevron.left", label: "Previous page", enabled: page > 0) { page -= 1 }
                ForEach(Array(Pagination.slots(current: page, pages: pages).enumerated()), id: \.offset) { _, slot in
                    if let slot {
                        Button { page = slot } label: {
                            Text("\(slot + 1)")
                                .font(Theme.display(13, relativeTo: .caption))
                                .foregroundStyle(slot == page ? Theme.foreground : Theme.muted)
                                .frame(width: 32, height: 32)
                                .background(slot == page ? Theme.controlFill : .clear, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Page \(slot + 1)")
                        .accessibilityAddTraits(slot == page ? .isSelected : [])
                    } else {
                        Text("…").foregroundStyle(Theme.muted).frame(width: 24, height: 32)
                    }
                }
                pageButton(symbol: "chevron.right", label: "Next page", enabled: page < pages - 1) { page += 1 }
            }
        }
    }

    private func pageButton(symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.caption.weight(.bold)).foregroundStyle(enabled ? Theme.foreground : Theme.muted.opacity(0.5)).frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    static func resultWord(_ result: String) -> String {
        switch result {
        case "W": "Win"
        case "L": "Loss"
        default: "Tie"
        }
    }

    static func resultColor(_ result: String) -> Color {
        switch result {
        case "W": Theme.success
        case "L": Theme.dangerText
        default: Theme.foregroundSecondary
        }
    }

    // MARK: Loading

    private func loadAll() async {
        isLoading = true
        fatal = nil
        let api = app.backend.api
        do {
            async let stats = api.statsView()
            async let hf = api.profileStatsFilters(scope: "human")
            async let cf = api.profileStatsFilters(scope: "cpu")
            all = try await stats
            humanFilters = (try? await hf) ?? humanFilters
            cpuFilters = (try? await cf) ?? cpuFilters
        } catch {
            fatal = (error as? APIError)?.detail ?? error.localizedDescription
        }
        isLoading = false
    }

    private func loadHumans() async {
        humans = try? await app.backend.api.statsViewHuman(boardSize: humanBoard, timer: humanTimer)
    }

    private func loadCPU() async {
        cpuRows = (try? await app.backend.api.statsViewCPU(boardSize: cpuBoard, timer: cpuTimer, cpuType: cpuType)) ?? []
    }

    private func loadHistory() async {
        isPaging = history != nil
        defer { isPaging = false }
        if let pageData = try? await app.backend.api.recentGames(limit: Self.pageSize, offset: page * Self.pageSize) {
            history = pageData
        }
    }
}

/// The numbers shown for one scope; CPU rows are combined like the web's `aggregateCpuRows`.
nonisolated struct StatsSummary: Equatable, Sendable {
    var games: Int
    var wins: Int
    var losses: Int
    var winPercentage: Double
    var highScore: Int
    var avgScore: Double
    var avgDurationMinutes: Double?

    init(_ stats: PlayerStatsView) {
        games = stats.totalGamesPlayed
        wins = stats.gamesWon
        losses = stats.gamesLost
        winPercentage = stats.winPercentage
        highScore = stats.highestScore
        avgScore = stats.avgFinalScore
        avgDurationMinutes = stats.totalGamesPlayed > 0 ? stats.avgGameDuration : nil
    }

    init(games: Int, wins: Int, losses: Int, winPercentage: Double, highScore: Int, avgScore: Double, avgDurationMinutes: Double?) {
        self.games = games
        self.wins = wins
        self.losses = losses
        self.winPercentage = winPercentage
        self.highScore = highScore
        self.avgScore = avgScore
        self.avgDurationMinutes = avgDurationMinutes
    }

    /// Sums the counts, weights the average score by games, averages the durations, takes the
    /// best high score; nil when there are no rows.
    static func combine(_ rows: [PlayerStatsCPUView]) -> StatsSummary? {
        guard !rows.isEmpty else { return nil }
        let games = rows.map(\.totalGamesPlayed).reduce(0, +)
        let wins = rows.map(\.gamesWon).reduce(0, +)
        let losses = rows.map(\.gamesLost).reduce(0, +)
        let weighted = rows.map { $0.avgFinalScore * Double($0.totalGamesPlayed) }.reduce(0, +)
        return StatsSummary(
            games: games,
            wins: wins,
            losses: losses,
            winPercentage: games > 0 ? Double(wins) / Double(games) * 100 : 0,
            highScore: rows.map(\.highestScore).max() ?? 0,
            avgScore: games > 0 ? weighted / Double(games) : 0,
            avgDurationMinutes: rows.map(\.avgGameDuration).reduce(0, +) / Double(rows.count)
        )
    }
}

/// Donut, Wins / Losses tiles and the 2×2 grid (web `StatsSummary` + `DonutContent`).
struct StatsSummaryView: View {
    let summary: StatsSummary

    private struct Slice: Identifiable {
        let id: String
        let value: Int
        let color: Color
    }

    var body: some View {
        let decided = summary.wins + summary.losses
        let slices = decided > 0
            ? [Slice(id: "wins", value: summary.wins, color: Theme.success), Slice(id: "losses", value: summary.losses, color: Theme.dangerText)]
            : [Slice(id: "none", value: 1, color: Theme.controlFill)]
        VStack(spacing: 20) {
            ZStack {
                Chart(slices) { slice in
                    SectorMark(angle: .value("Games", slice.value), innerRadius: .ratio(0.72), angularInset: slices.count > 1 ? 1.5 : 0)
                        .cornerRadius(10)
                        .foregroundStyle(slice.color)
                }
                .chartLegend(.hidden)
                VStack(spacing: 2) {
                    Text(summary.games > 0 ? String(format: "%.1f%%", summary.winPercentage) : "—")
                        .font(Theme.display(36, relativeTo: .largeTitle)).monospacedDigit().foregroundStyle(Theme.foreground)
                    Text("WIN RATE").font(Theme.display(10, relativeTo: .caption2)).tracking(1.5).foregroundStyle(Theme.muted)
                    Text("\(decided) games").font(.caption).foregroundStyle(Theme.muted)
                }
            }
            .frame(width: 200, height: 200)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Win rate \(summary.games > 0 ? String(format: "%.1f", summary.winPercentage) : "none") percent over \(decided) games")

            HStack(spacing: 12) {
                tile { Stat(label: "Wins", value: "\(summary.wins)", tone: .success) }
                tile { Stat(label: "Losses", value: "\(summary.losses)", tone: .danger) }
            }
            Grid(horizontalSpacing: 12, verticalSpacing: 14) {
                GridRow {
                    Stat(label: "Games played", value: "\(summary.games)", symbol: "gamecontroller").frame(maxWidth: .infinity, alignment: .leading)
                    Stat(label: "High score", value: "\(summary.highScore)", symbol: "flame").frame(maxWidth: .infinity, alignment: .leading)
                }
                GridRow {
                    Stat(label: "Avg score", value: "\(Int(summary.avgScore.rounded()))", symbol: "target").frame(maxWidth: .infinity, alignment: .leading)
                    Stat(label: "Avg duration", value: summary.avgDurationMinutes.map { "\(Int($0.rounded())) min" } ?? "—", symbol: "clock").frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func tile<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border))
    }
}

/// The web's seven-slot pager: `0 1 2 3 4 … last`, `0 … p-1 p p+1 … last`, `0 … last-4 … last`.
nonisolated enum Pagination {
    static func slots(current: Int, pages: Int) -> [Int?] {
        guard pages > 7 else { return Array(0..<pages) }
        if current <= 3 { return [0, 1, 2, 3, 4, nil, pages - 1] }
        if current >= pages - 4 { return [0, nil, pages - 5, pages - 4, pages - 3, pages - 2, pages - 1] }
        return [0, nil, current - 1, current, current + 1, nil, pages - 1]
    }
}
