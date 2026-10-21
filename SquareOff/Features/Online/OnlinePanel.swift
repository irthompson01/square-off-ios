import SquareOffNet
import SwiftUI

/// The Online section of the Play page (web `OnlinePanel`): quick-match status strip, then
/// Create / Quick match / Join / Rooms tabs. The sticky primary action lives on the page.
struct OnlinePanel: View {
    @Environment(AppModel.self) private var app
    @Bindable var setup: PlaySetupModel
    let onJoinRoom: () -> Void
    @State private var joinTouched = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Online")
            VStack(alignment: .leading, spacing: 16) {
                if let record = app.online.rejoinable { rejoinStrip(record) }
                matchStrip
                SegmentedPills(options: PlaySetupModel.OnlineTab.allCases, selection: $setup.onlineTab, title: \.title, compact: true)
                switch setup.onlineTab {
                case .create: createTab
                case .quick: quickTab
                case .join: joinTab
                case .rooms: OpenRoomsList(boardSize: setup.boardSize, timer: setup.timer, onSwitch: { setup.onlineTab = $0 }, onJoin: join)
                }
            }
            .padding(14)
            .card()
            Label(app.backend.isLive ? "Playing on the local server" : "Playing against the in-app room server (bots will join you)",
                  systemImage: app.backend.isLive ? "server.rack" : "cpu")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
    }

    // MARK: Strips

    @ViewBuilder
    private var matchStrip: some View {
        switch app.online.state {
        case .matching(_, let message):
            HStack(spacing: 10) {
                ProgressView().controlSize(.small).tint(Theme.link)
                Text(message).font(.subheadline).foregroundStyle(Theme.foreground)
                Spacer()
                Button("Cancel") { Task { await app.online.cancelQuickMatch() } }
                    .buttonStyle(TertiaryButtonStyle(small: true, fullWidth: false))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.accent.opacity(0.3)))
            .accessibilityElement(children: .combine)
        default:
            EmptyView()
        }
    }

    private func rejoinStrip(_ record: OnlineSessionRecord) -> some View {
        AlertBox(.warning, title: "Back to room \(record.roomCode)?",
                 message: "You were \(record.role == .host ? "hosting" : record.role == .spectator ? "watching" : "playing in") this room a moment ago.") {
            Button { join(record.roomCode) } label: { Label("Rejoin", systemImage: "arrow.uturn.left") }
                .buttonStyle(SecondaryButtonStyle(small: true, fullWidth: false))
                .padding(.top, 4)
        }
    }

    // MARK: Tabs

    private var createTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            tabHeading("Create a room", "You get a room code to share. The game starts when you're ready.")
            SettingsToggle(title: "List in public lobby", description: "Anyone browsing Rooms can see and join it.", isOn: $setup.listPublic)
        }
    }

    private var quickTab: some View {
        tabHeading("Quick match",
                   "Pairs you with someone who wants a \(setup.boardSize) × \(setup.boardSize) game with \(PlaySetupModel.timerPhrase(setup.timer)). If nobody is waiting, you host and the next player joins you.")
    }

    private var joinTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            tabHeading("Join with a code", nil)
            LabeledField(label: "Room code",
                         help: "Ask the host for the code shown in their room.",
                         error: joinTouched && !setup.isJoinCodeValid ? "Enter the 1–6 digit code from your host." : nil) {
                TextField("e.g. 4821", text: $setup.joinCode)
                    .keyboardType(.numberPad)
                    .font(Theme.display(17, relativeTo: .headline))
                    .tracking(3)
                    .foregroundStyle(Theme.foreground)
                    .onChange(of: setup.joinCode) { _, _ in setup.sanitizeJoinCode() }
                    .onSubmit { joinTouched = true }
            }
            .onDisappear { joinTouched = false }
        }
    }

    private func tabHeading(_ title: String, _ text: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Theme.display(16, relativeTo: .headline)).foregroundStyle(Theme.foreground)
            if let text {
                Text(text).font(.subheadline).foregroundStyle(Theme.foregroundSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func join(_ code: Int) {
        onJoinRoom()
        Task { await app.online.join(code: code) }
    }
}

/// `GET /matcher/open` for the chosen board and timer, polled every 10 s while visible
/// (web `OpenRoomsList` + `useOpenRooms`).
struct OpenRoomsList: View {
    @Environment(AppModel.self) private var app
    let boardSize: Int
    let timer: Int
    let onSwitch: (PlaySetupModel.OnlineTab) -> Void
    let onJoin: (Int) -> Void

    @State private var rooms: [OpenRoomDTO] = []
    @State private var loaded = false
    @State private var failed = false
    @State private var refreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Open rooms").font(Theme.display(16, relativeTo: .headline)).foregroundStyle(Theme.foreground)
                Spacer()
                Button {
                    Task { await refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .symbolEffect(.rotate, isActive: refreshing)
                }
                .buttonStyle(TertiaryButtonStyle(small: true, fullWidth: false))
            }
            if !loaded {
                ForEach(0..<3, id: \.self) { _ in
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            SkeletonBar(width: 120)
                            SkeletonBar(width: 200, height: 10)
                        }
                        Spacer()
                        SkeletonBar(width: 56, height: 32)
                    }
                    .padding(12)
                    .card(fill: Theme.surfaceSecondary, radius: 12)
                }
            } else if failed {
                AlertBox(.danger, title: "Couldn't load open rooms", message: "Check your connection and refresh.")
            } else if rooms.isEmpty {
                EmptyState(symbol: "globe", title: "No open rooms",
                           text: "Nobody is hosting a \(boardSize) × \(boardSize) game with \(PlaySetupModel.timerPhrase(timer)) right now. Create one or try Quick Match.") {
                    Button("Create Room") { onSwitch(.create) }.buttonStyle(SecondaryButtonStyle(small: true, fullWidth: false))
                    Button("Quick Match") { onSwitch(.quick) }.buttonStyle(SecondaryButtonStyle(small: true, fullWidth: false))
                }
            } else {
                ForEach(rooms) { room in
                    let full = room.slotsFilled >= room.slotsMax
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(room.hostLabel).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.foreground).lineLimit(1)
                            (Text("Room \(room.roomCode)").font(Theme.display(13, relativeTo: .footnote))
                                + Text(" · \(room.slotsFilled)/\(room.slotsMax) players · \(room.boardSize) × \(room.boardSize) · \(PlaySetupModel.timerLabel(room.timer))").font(.footnote))
                                .foregroundStyle(Theme.foregroundSecondary)
                            Text("listed \(RelativeAgo.fine(Date(timeIntervalSince1970: room.lastHeartbeat > 1e12 ? room.lastHeartbeat / 1000 : room.lastHeartbeat)))")
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        if full { Chip(text: "Full") }
                        Button("Join") { onJoin(room.roomCode) }
                            .buttonStyle(SecondaryButtonStyle(small: true, fullWidth: false))
                            .disabled(full)
                            .opacity(full ? 0.5 : 1)
                            .accessibilityLabel("Join room \(room.roomCode)")
                    }
                    .padding(12)
                    .card(fill: Theme.surfaceSecondary, radius: 12)
                }
            }
        }
        .task(id: "\(boardSize)-\(timer)") {
            loaded = false
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func refresh() async {
        refreshing = true
        defer { refreshing = false }
        do {
            rooms = try await app.backend.matcher.openRooms(boardSize: boardSize, timer: timer, limit: 50, offset: 0)
            failed = false
        } catch {
            failed = true
        }
        loaded = true
    }
}
