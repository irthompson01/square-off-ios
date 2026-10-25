import SquareOffNet
import SwiftUI

// Pieces every section shares: status chips, the error box with Try again, skeleton rows, the
// page strip, and the polling modifier.

enum AdminChips {
    static func role(_ role: AppRole) -> Chip {
        Chip(text: role.rawValue, style: role == .superadmin ? .accent : .default)
    }

    static func active(_ isActive: Bool) -> Chip {
        Chip(text: isActive ? "Active" : "Inactive", style: isActive ? .success : .danger, dot: true)
    }

    static func phase(_ room: AdminLiveRoom) -> Chip {
        switch room.phase {
        case .lobby: Chip(text: "Lobby", style: .default)
        case .playing: Chip(text: "Playing", style: .success, dot: true)
        case .gameOver: Chip(text: "Game over", style: .accent)
        case .hostAway: Chip(text: "Host away · \(Int(room.hostAwaySeconds ?? 0)) s", style: .warning, dot: true)
        case .unknown: Chip(text: room.phase.rawValue, style: .default)
        }
    }

    static func gameType(_ type: String, isCPU: Bool) -> Chip {
        if isCPU { return Chip(text: "CPU", style: .warning) }
        return Chip(text: type == "online" ? "Online" : "Local", style: type == "online" ? .accent : .default)
    }

    static func result(_ result: AdminUserGameResult) -> Chip {
        switch result {
        case .win: Chip(text: "Win", style: .success)
        case .loss: Chip(text: "Loss", style: .danger)
        case .tie: Chip(text: "Tie", style: .default)
        case .unfinished, .unknown: Chip(text: "Unfinished", style: .warning)
        }
    }

    static func feedback(_ status: FeedbackStatus) -> Chip {
        status == .handled ? Chip(text: "Handled", style: .success) : Chip(text: "New", style: .accent)
    }

    static func provider(_ provider: String?) -> Chip {
        Chip(text: provider ?? "password", style: .default)
    }
}

/// `AlertBox(.danger)` with a retry action (web `SectionError`).
struct SectionError: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        AlertBox(.danger, title: "Couldn't load this section", message: message) {
            Button("Try again", action: retry).buttonStyle(SecondaryButtonStyle(small: true, fullWidth: false))
        }
    }
}

struct SkeletonRows: View {
    var count = 6

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { _ in
                HStack {
                    SkeletonBar(width: 140)
                    Spacer()
                    SkeletonBar(width: 72)
                }
                .padding(.vertical, 14)
            }
        }
        .accessibilityLabel("Loading")
    }
}

/// "1–50 of 230" with previous / numbered / next (same slots as the stats history pager).
struct PageStrip<Item: Sendable, Query: Equatable & Sendable>: View {
    let list: PagedQuery<Item, Query>

    var body: some View {
        if list.total > PagedQuery<Item, Query>.pageSize {
            VStack(alignment: .leading, spacing: 10) {
                Text(list.rangeLabel).font(.subheadline).foregroundStyle(Theme.foregroundSecondary)
                HStack(spacing: 4) {
                    button("chevron.left", "Previous page", enabled: list.page > 0) { Task { await list.goTo(page: list.page - 1) } }
                    ForEach(Array(Pagination.slots(current: list.page, pages: list.pages).enumerated()), id: \.offset) { _, slot in
                        if let slot {
                            Button { Task { await list.goTo(page: slot) } } label: {
                                Text("\(slot + 1)")
                                    .font(Theme.display(13, relativeTo: .caption))
                                    .foregroundStyle(slot == list.page ? Theme.foreground : Theme.muted)
                                    .frame(width: 32, height: 32)
                                    .background(slot == list.page ? Theme.controlFill : .clear, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Page \(slot + 1)")
                        } else {
                            Text("…").foregroundStyle(Theme.muted).frame(width: 24, height: 32)
                        }
                    }
                    button("chevron.right", "Next page", enabled: list.page < list.pages - 1) { Task { await list.goTo(page: list.page + 1) } }
                }
            }
            .padding(.top, 8)
        } else if list.total > 0 {
            Text("\(list.total) \(list.total == 1 ? "item" : "items")").font(.caption).foregroundStyle(Theme.muted).padding(.top, 4)
        }
    }

    private func button(_ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.caption.weight(.bold)).foregroundStyle(enabled ? Theme.foreground : Theme.muted.opacity(0.5)).frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// `.task` that refreshes every `interval` while the view is on screen and the scene is
/// active (the same loop as the open-rooms list); a scene change restarts it, which refreshes
/// at once on return.
struct AdminPolling: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let interval: Duration
    let enabled: Bool
    let action: @Sendable () async -> Void

    func body(content: Content) -> some View {
        content.task(id: "\(enabled)-\(scenePhase == .active)") {
            guard scenePhase == .active else { return }
            await action()
            guard enabled else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                await action()
            }
        }
    }
}

extension View {
    func adminPolling(every interval: Duration, enabled: Bool = true, _ action: @escaping @Sendable () async -> Void) -> some View {
        modifier(AdminPolling(interval: interval, enabled: enabled, action: action))
    }
}

/// "Updated 4 s ago", ticking once a second without re-rendering the rest of the screen.
struct UpdatedAgo: View {
    let date: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(label(now: context.date)).font(.caption).foregroundStyle(Theme.muted).monospacedDigit()
        }
    }

    private func label(now: Date) -> String {
        guard let date else { return "Not loaded yet" }
        let seconds = Int(now.timeIntervalSince(date))
        return seconds < 2 ? "Updated just now" : "Updated \(seconds) s ago"
    }
}

/// A game id on its way to `AdminReplaySheet` (`.sheet(item:)`).
struct ReplayTarget: Identifiable, Equatable {
    let id: Int
}

/// The player app's replay screen over the admin endpoint (any game, finished or not).
struct AdminReplaySheet: View {
    @Environment(AppModel.self) private var app
    let gameID: Int

    var body: some View {
        NavigationStack {
            ReplayView(gameID: gameID, load: { try await app.admin.replay(gameID: $0) })
        }
        .presentationBackground(Theme.overlay)
    }
}

/// A labelled key/value row inside a card.
struct DetailRow: View {
    let label: String
    let value: String
    var dim = false

    var body: some View {
        HStack(alignment: .top) {
            Text(label).font(.subheadline).foregroundStyle(Theme.muted)
            Spacer(minLength: 12)
            Text(value).font(.subheadline.weight(.medium)).foregroundStyle(dim ? Theme.muted : Theme.foreground)
                .multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .padding(.vertical, 8)
    }
}
