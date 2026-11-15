import SquareOffNet
import SwiftUI

/// Every in-memory room, the public lobby and the quick-match queue, refreshed every 5 s
/// (web `pages/admin/live.tsx`).
struct LiveView: View {
    @Environment(AppModel.self) private var app
    @Environment(AdminAppModel.self) private var console
    @State private var query: AdminQuery<AdminLiveSnapshot>?
    @State private var replay: ReplayTarget?

    var body: some View {
        @Bindable var console = console
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeading(title: "Live", description: "Rooms, the open lobby and the quick-match queue, straight from the game server's memory.")
                HStack {
                    UpdatedAgo(date: query?.updatedAt)
                    Spacer()
                    Toggle("Auto-refresh", isOn: $console.liveAutoRefresh).toggleStyle(.switch).tint(Theme.accent).labelsHidden()
                    Text("Auto-refresh").font(.caption).foregroundStyle(Theme.foregroundSecondary)
                }
                if let query {
                    if let error = query.error, query.value == nil {
                        SectionError(message: error) { Task { await query.refresh() } }
                    } else if let snapshot = query.value {
                        content(snapshot, staleError: query.error)
                    } else {
                        SkeletonRows(count: 5).padding(16).card()
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 960)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("Live")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await query?.refresh() }
        .onAppear { if query == nil { let api = app.admin; query = AdminQuery { try await api.live() } } }
        .adminPolling(every: .seconds(5), enabled: console.liveAutoRefresh) { await query?.refresh() }
        .sheet(item: $replay) { target in AdminReplaySheet(gameID: target.id) }
    }

    @ViewBuilder
    private func content(_ snapshot: AdminLiveSnapshot, staleError: String?) -> some View {
        if let staleError {
            Text("Last refresh failed: \(staleError)").font(.caption).foregroundStyle(Theme.warning)
        }
        HStack(spacing: 10) {
            Stat(label: "Sockets", value: "\(snapshot.websocket.connections)").frame(maxWidth: .infinity, alignment: .leading)
            Stat(label: "In rooms", value: "\(snapshot.websocket.inRooms)").frame(maxWidth: .infinity, alignment: .leading)
            Stat(label: "Rooms", value: "\(snapshot.rooms.count)").frame(maxWidth: .infinity, alignment: .leading)
            Stat(label: "Queue", value: "\(snapshot.matchQueue.tickets)", tone: snapshot.matchQueue.tickets > 0 ? .warning : .default).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .card()

        SectionLabel("Rooms · \(snapshot.rooms.count)")
        if snapshot.rooms.isEmpty {
            EmptyState(symbol: "dot.radiowaves.left.and.right", title: "No rooms", text: "Nobody is hosting right now.")
        }
        ForEach(snapshot.rooms) { room in roomCard(room) }

        DisclosureGroup {
            if snapshot.openRooms.isEmpty {
                Text("Nothing listed.").font(.caption).foregroundStyle(Theme.muted).padding(.vertical, 8)
            }
            ForEach(snapshot.openRooms) { room in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Room \(String(room.roomCode)) · \(room.hostLabel)").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.foreground)
                        Text("\(room.slotsFilled)/\(room.slotsMax) seats · \(room.boardSize)×\(room.boardSize) · \(room.timer == 0 ? "No timer" : "\(room.timer) s") · listed \(AdminFormat.duration(room.ageS)) ago · heartbeat \(AdminFormat.duration(room.heartbeatAgeS)) ago")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    if !room.listed { Chip(text: "Unlisted") }
                }
                .padding(.vertical, 8)
            }
        } label: {
            Text("Open lobby · \(snapshot.openRooms.count)").font(Theme.display(14, relativeTo: .subheadline)).foregroundStyle(Theme.foreground)
        }
        .tint(Theme.link)
        .padding(16)
        .card()

        DisclosureGroup {
            if snapshot.matchQueue.items.isEmpty {
                Text("Nobody is waiting.").font(.caption).foregroundStyle(Theme.muted).padding(.vertical, 8)
            }
            ForEach(snapshot.matchQueue.items) { ticket in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Ticket \(ticket.ticketId)").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.foreground)
                        Text("\(ticket.boardSize)×\(ticket.boardSize) · \(ticket.timer == 0 ? "No timer" : "\(ticket.timer) s") · waiting \(AdminFormat.duration(ticket.waitS))")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    if let code = ticket.assignedRoomCode { Chip(text: "Room \(String(code))", style: .accent) }
                    else if ticket.shouldCreateRoom { Chip(text: "Will host", style: .warning) }
                    else { Chip(text: ticket.acknowledged ? "Queued" : "New") }
                }
                .padding(.vertical, 8)
            }
        } label: {
            Text("Quick-match queue · \(snapshot.matchQueue.tickets)\(snapshot.matchQueue.oldestWaitS.map { " · oldest \(AdminFormat.duration($0))" } ?? "")")
                .font(Theme.display(14, relativeTo: .subheadline)).foregroundStyle(Theme.foreground)
        }
        .tint(Theme.link)
        .padding(16)
        .card()
    }

    private func roomCard(_ room: AdminLiveRoom) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Room \(String(room.roomCode))").font(Theme.display(16, relativeTo: .headline)).foregroundStyle(Theme.foreground)
                AdminChips.phase(room)
                Spacer()
                if room.phase == .gameOver, let gameID = room.gameId {
                    Button("Replay") { replay = ReplayTarget(id: gameID) }.buttonStyle(SecondaryButtonStyle(small: true, fullWidth: false))
                }
            }
            Text("\(room.boardSize)×\(room.boardSize) · \(room.timer == 0 ? "No timer" : "\(room.timer) s") · \(room.movesPlayed) moves · \(room.spectatorCount) watching\(room.gameId.map { " · game #\(String($0))" } ?? "")")
                .font(.caption).foregroundStyle(Theme.muted)
            ForEach(room.players) { player in
                HStack(spacing: 8) {
                    Circle().fill(player.connected ? Theme.success : Theme.dangerText).frame(width: 8, height: 8)
                    Text("\(player.slot). \(player.name)").font(.subheadline).foregroundStyle(Theme.foreground)
                    if player.isCPU { Chip(text: "CPU", style: .warning) }
                    if room.turnIndex == player.slot - 1, room.phase == .playing { Chip(text: "Turn", style: .accent) }
                    if let away = player.awaySeconds { Text("away \(Int(away)) s").font(.caption).foregroundStyle(Theme.warning) }
                    Spacer()
                    Text("\(player.score)").font(Theme.display(14, relativeTo: .subheadline)).monospacedDigit().foregroundStyle(Theme.foreground)
                }
            }
        }
        .padding(16)
        .card()
    }
}
