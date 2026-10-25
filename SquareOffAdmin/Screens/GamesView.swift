import SquareOffNet
import SwiftUI

/// Every game by every player, with filters, a seats sheet and the admin replay
/// (web `pages/admin/games.tsx`).
struct GamesView: View {
    @Environment(AppModel.self) private var app
    @Environment(AdminAppModel.self) private var console
    @State private var list: PagedQuery<AdminGameRow, AdminGameQuery>?
    @State private var draft = AdminGameQuery()
    @State private var cpuTypes: [String] = []
    @State private var showsFilters = false
    @State private var seats: AdminGameRow?
    @State private var replay: ReplayTarget?

    var body: some View {
        @Bindable var console = console
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeading(title: "Games", description: "Newest first. Tap a game for its seats and scores; finished ones replay.")
                HStack(spacing: 8) {
                    sortMenu
                    Button { showsFilters = true } label: { Label(draft.hasFilters ? "Filters · on" : "Filters", systemImage: "line.3.horizontal.decrease.circle") }
                        .buttonStyle(SecondaryButtonStyle(small: true, fullWidth: false))
                    Spacer()
                    if let list { Text(list.rangeLabel).font(.caption).foregroundStyle(Theme.muted) }
                }
                if let list {
                    if let error = list.error, list.items.isEmpty {
                        SectionError(message: error) { Task { await list.load() } }
                    } else if list.status == .loading {
                        SkeletonRows().padding(.horizontal, 16).card()
                    } else if list.items.isEmpty {
                        EmptyState(symbol: "gamecontroller", title: "No games match", text: "Try other filters.") {
                            if draft.hasFilters {
                                Button("Clear filters") { draft = AdminGameQuery(); Task { await list.setQuery(draft) } }
                                    .buttonStyle(SecondaryButtonStyle(small: true, fullWidth: false))
                            }
                        }
                    } else {
                        VStack(spacing: 0) {
                            ForEach(list.items) { game in
                                Button { seats = game } label: { row(game) }.buttonStyle(.plain)
                                if game.id != list.items.last?.id { Theme.separator.frame(height: 1) }
                            }
                        }
                        .padding(.horizontal, 16)
                        .card()
                        .opacity(list.isBusy ? 0.6 : 1)
                        PageStrip(list: list)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 960)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("Games")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if list == nil {
                let api = app.admin
                list = PagedQuery(query: draft) { query, page in
                    var q = query
                    q.page = page
                    let result = try await api.games(q)
                    return (result.total, result.items)
                }
                Task {
                    await list?.load()
                    cpuTypes = (try? await api.cpus().map(\.cpuType)) ?? []
                }
            }
        }
        .sheet(isPresented: $showsFilters) {
            GameFiltersSheet(query: $draft, cpuTypes: cpuTypes) { Task { await list?.setQuery(draft) } }
                .presentationDetents([.large])
                .presentationBackground(Theme.overlay)
        }
        .sheet(item: $seats) { game in
            GameSeatsSheet(game: game) { replay = ReplayTarget(id: game.id) }
                .presentationDetents([.medium, .large])
                .presentationBackground(Theme.overlay)
        }
        .sheet(item: $replay) { target in AdminReplaySheet(gameID: target.id) }
        .onChange(of: console.pendingReplay, initial: true) { _, id in
            guard let id else { return }
            console.pendingReplay = nil
            replay = ReplayTarget(id: id)
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(AdminGameSort.allCases, id: \.self) { sort in
                Button {
                    if draft.sort == sort { draft.dir = draft.dir == .asc ? .desc : .asc } else { draft.sort = sort; draft.dir = .desc }
                    Task { await list?.setQuery(draft) }
                } label: { Label(Self.sortTitle(sort), systemImage: draft.sort == sort ? (draft.dir == .asc ? "chevron.up" : "chevron.down") : "") }
            }
        } label: {
            Label("\(Self.sortTitle(draft.sort)) \(draft.dir == .asc ? "↑" : "↓")", systemImage: "arrow.up.arrow.down")
        }
        .buttonStyle(SecondaryButtonStyle(small: true, fullWidth: false))
    }

    static func sortTitle(_ sort: AdminGameSort) -> String {
        switch sort {
        case .startTime: "Started"
        case .endTime: "Ended"
        case .duration: "Duration"
        }
    }

    private func row(_ game: AdminGameRow) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("#\(String(game.id))").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.foreground)
                    AdminChips.gameType(game.type, isCPU: game.isCpu)
                    if game.endTime == nil { Chip(text: "Unfinished", style: .warning) }
                }
                Text(game.participants.map(\.displayName).joined(separator: " vs ")).font(.caption).foregroundStyle(Theme.foregroundSecondary).lineLimit(1)
                Text("\(game.boardSize)×\(game.boardSize) · \(game.timer == 0 ? "no timer" : "\(game.timer) s") · \(AdminFormat.relative(game.startTime)) · \(AdminFormat.duration(game.durationSec.map(Double.init)))\(game.winnerDisplay.map { " · won by \($0)" } ?? (game.endTime != nil ? " · tie" : ""))")
                    .font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

struct GameFiltersSheet: View {
    @Binding var query: AdminGameQuery
    let cpuTypes: [String]
    let onApply: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var range: Range = .any

    enum Range: String, CaseIterable, Identifiable {
        case any, week, month, quarter
        var id: String { rawValue }
        var title: String {
            switch self {
            case .any: "Any time"
            case .week: "Last 7 days"
            case .month: "Last 30 days"
            case .quarter: "Last 90 days"
            }
        }
        var days: Int? {
            switch self {
            case .any: nil
            case .week: 7
            case .month: 30
            case .quarter: 90
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $query.type) {
                    Text("Any").tag(AdminGameQuery.GameType?.none)
                    ForEach(AdminGameQuery.GameType.allCases, id: \.self) { Text($0.rawValue.capitalized).tag(AdminGameQuery.GameType?.some($0)) }
                }
                Picker("CPU", selection: $query.cpuType) {
                    Text("Any").tag(String?.none)
                    ForEach(cpuTypes, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                Picker("Board", selection: $query.boardSize) {
                    Text("Any").tag(Int?.none)
                    ForEach([6, 7, 8, 9, 10, 11, 12], id: \.self) { Text("\($0)×\($0)").tag(Int?.some($0)) }
                }
                Picker("Timer", selection: $query.timer) {
                    Text("Any").tag(Int?.none)
                    ForEach([0, 5, 10, 15, 20, 30, 40, 50, 60], id: \.self) { Text($0 == 0 ? "No timer" : "\($0) s").tag(Int?.some($0)) }
                }
                Picker("Winner", selection: $query.winner) {
                    Text("Any").tag(AdminGameWinnerFilter?.none)
                    ForEach(AdminGameWinnerFilter.allCases, id: \.self) { Text($0.rawValue.capitalized).tag(AdminGameWinnerFilter?.some($0)) }
                }
                Picker("Started", selection: $range) {
                    ForEach(Range.allCases) { Text($0.title).tag($0) }
                }
                Stepper("Min duration: \(query.minDuration.map { "\($0) s" } ?? "any")", value: Binding(get: { query.minDuration ?? 0 }, set: { query.minDuration = $0 > 0 ? $0 : nil }), in: 0...3600, step: 60)
                Button("Clear filters") { query = AdminGameQuery(sort: query.sort, dir: query.dir); range = .any }.disabled(!query.hasFilters)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        if let days = range.days {
                            query.from = AdminFormat.queryDay(Date().addingTimeInterval(-Double(days - 1) * 86_400))
                            query.to = AdminFormat.queryDay(Date().addingTimeInterval(86_400))
                        } else {
                            query.from = nil
                            query.to = nil
                        }
                        onApply()
                        dismiss()
                    }
                }
            }
        }
        .onAppear { range = query.from == nil ? .any : range }
    }
}

struct GameSeatsSheet: View {
    @Environment(AdminAppModel.self) private var console
    @Environment(\.dismiss) private var dismiss
    let game: AdminGameRow
    let onReplay: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 6) {
                        AdminChips.gameType(game.type, isCPU: game.isCpu)
                        Chip(text: "\(game.boardSize)×\(game.boardSize)")
                        Chip(text: game.timer == 0 ? "No timer" : "\(game.timer) s")
                        if game.endTime == nil { Chip(text: "Unfinished", style: .warning) }
                    }
                    VStack(spacing: 0) {
                        DetailRow(label: "Started", value: AdminFormat.absolute(game.startTime))
                        DetailRow(label: "Ended", value: AdminFormat.absolute(game.endTime), dim: game.endTime == nil)
                        DetailRow(label: "Duration", value: AdminFormat.duration(game.durationSec.map(Double.init)))
                        DetailRow(label: "Winner", value: game.winnerDisplay ?? (game.endTime != nil ? "Tie" : "—"), dim: game.winnerDisplay == nil)
                    }
                    .padding(.horizontal, 16)
                    .card()
                    SectionLabel("Seats")
                    ForEach(game.participants.sorted { $0.participantOrder < $1.participantOrder }) { seat in
                        HStack(spacing: 10) {
                            Circle().fill(Color(hex: seat.color)).frame(width: 12, height: 12)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(seat.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.foreground)
                                    Chip(text: seat.participantType.rawValue, style: seat.participantType == .cpu ? .warning : .default)
                                    if seat.isWinner { Chip(text: "Winner", style: .success, symbol: "crown") }
                                }
                                Text(seat.userId ?? seat.guestId ?? seat.cpuType ?? "—").font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                            Spacer()
                            Text(seat.finalScore.map(String.init) ?? "—").font(Theme.display(16, relativeTo: .headline)).monospacedDigit().foregroundStyle(Theme.foreground)
                            if let userId = seat.userId {
                                Button { dismiss(); console.open(user: userId) } label: { Image(systemName: "person.crop.circle").foregroundStyle(Theme.link) }
                                    .buttonStyle(.plain).accessibilityLabel("Open \(seat.displayName)")
                            }
                        }
                        .padding(12)
                        .card(fill: Theme.surfaceSecondary, radius: 12)
                    }
                    Button { dismiss(); onReplay() } label: { Label("Replay", systemImage: "play.fill") }
                        .buttonStyle(PrimaryButtonStyle())
                }
                .padding(16)
            }
            .background(Theme.overlay)
            .navigationTitle("Game #\(String(game.id))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
