import SquareOffNet
import SwiftUI

/// Online hub: quick match, join by code, create a room, browse the lobby, rejoin.
/// Every action goes through `app.online` (the `RoomCoordinator`), which talks to the mock room
/// server or the docker stack depending on the backend.
struct OnlineHubView: View {
    @Environment(AppModel.self) private var app
    @State private var boardSize = 8
    @State private var timer = 20
    @State private var roomCode = ""
    @State private var listPublic = true
    @State private var showRoom = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let record = app.online.rejoinable { rejoinCard(record) }
                quickMatch
                joinFriend
                createRoom
                NavigationLink { OpenRoomsView() } label: {
                    row("Browse open rooms", systemImage: "list.bullet")
                }
                .buttonStyle(.plain)
                .card()
                Label(app.backend.isLive ? "Playing on the local server" : "Playing against the in-app room server (bots will join you)",
                      systemImage: app.backend.isLive ? "server.rack" : "cpu")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 4)
            }
            .padding(16)
        }
        .appBackground()
        .navigationTitle("Online")
        .navigationDestination(isPresented: $showRoom) { WaitingRoomView() }
        .task {
            app.online.refreshRejoinable()
            if let code = app.pendingJoinCode {
                app.pendingJoinCode = nil
                roomCode = String(code)
                join(code)
            } else if app.pendingOnlineRoom {
                app.pendingOnlineRoom = false
                showRoom = true
            }
        }
    }

    private func rejoinCard(_ record: OnlineSessionRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Back to room \(record.roomCode)?").font(.title3.bold())
            Text("You were \(record.role == .host ? "hosting" : record.role == .spectator ? "watching" : "playing in") this room a moment ago.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Button { join(record.roomCode) } label: { Label("Rejoin", systemImage: "arrow.uturn.left") }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(16)
        .card(tint: Theme.warning)
    }

    private var quickMatch: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quick Match").font(.title3.bold())
                Spacer()
                optionsMenu
            }
            Text("We'll pair you with someone who picked the same board and timer.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Button {
                showRoom = true
                Task { await app.online.quickMatch(boardSize: boardSize, timer: timer) }
            } label: {
                Label("Find a match", systemImage: "magnifyingglass")
            }
            .buttonStyle(PrimaryButtonStyle(color: Theme.go))
        }
        .padding(16)
        .card(tint: Color(hex: "#50C878"))
    }

    private var optionsMenu: some View {
        Menu {
            Picker("Board", selection: $boardSize) {
                ForEach(SetupForm.boardSizes, id: \.self) { Text("\($0)×\($0)").tag($0) }
            }
            Picker("Timer", selection: $timer) {
                ForEach(SetupForm.timers, id: \.self) { Text($0 == 0 ? "No timer" : "\($0)s").tag($0) }
            }
        } label: {
            Label("\(boardSize)×\(boardSize) · \(timer == 0 ? "No timer" : "\(timer)s")", systemImage: "chevron.down")
                .labelStyle(.titleAndIcon)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Theme.surfaceRaised, in: Capsule())
        }
    }

    private var joinFriend: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Join a friend").font(.title3.bold())
            HStack(spacing: 10) {
                TextField("Room code", text: $roomCode)
                    .keyboardType(.numberPad)
                    .font(.title3.monospaced().weight(.semibold))
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 14))
                    .onChange(of: roomCode) { _, value in roomCode = String(value.filter(\.isNumber).prefix(6)) }
                Button {
                    if let code = Int(roomCode) { join(code) }
                } label: {
                    Text("Join").font(.headline).padding(.horizontal, 20).frame(height: 50)
                        .background(Color(hex: "#0583D2"), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(roomCode.isEmpty)
                .opacity(roomCode.isEmpty ? 0.5 : 1)
            }
            Text("Or open an invite link: it lands right in the room.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(16)
        .card()
    }

    private var createRoom: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Create a room").font(.title3.bold())
                Spacer()
                optionsMenu
            }
            Toggle("List it in the open rooms lobby", isOn: $listPublic)
                .font(.subheadline)
            Button {
                showRoom = true
                Task { await app.online.host(boardSize: boardSize, timer: timer, listPublic: listPublic) }
            } label: {
                Label("Create room", systemImage: "plus.square")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(16)
        .card()
    }

    private func join(_ code: Int) {
        showRoom = true
        Task { await app.online.join(code: code) }
    }

    private func row(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage).foregroundStyle(Theme.link).frame(width: 24)
            Text(title).font(.headline)
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
    }
}

/// The lobby of one room, driven by `RoomCoordinator.state`: searching, connecting, waiting for
/// players, failures. Pops itself when the coordinator goes idle.
struct WaitingRoomView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var failure: RoomCoordinator.OnlineError?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                codeCard
                if let info = app.online.state.roomInfo { seats(info) }
            }
            .padding(16)
        }
        .appBackground()
        .safeAreaInset(edge: .bottom) { bottomBar.padding(16) }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(app.online.state.roomInfo != nil)
        .toolbar {
            if app.online.state.roomInfo != nil || app.online.state.isBusy {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Leave") { Task { await app.online.leave() } }
                }
            }
        }
        .onChange(of: app.online.state) { _, state in
            switch state {
            case .idle: dismiss()
            case .failed(let error): failure = error
            default: break
            }
        }
        .alert("Couldn't join", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK") { Task { await app.online.leave() } }
        } message: {
            Text(failure?.message ?? "")
        }
    }

    private var title: String {
        switch app.online.state {
        case .matching: "Finding a match"
        case .connecting, .creating, .joining: "Connecting"
        default: "Waiting room"
        }
    }

    private var codeCard: some View {
        VStack(spacing: 10) {
            switch app.online.state {
            case .matching(_, let message):
                SectionLabel("Quick match")
                ProgressView().controlSize(.large).padding(.vertical, 8)
                Text(message).font(.subheadline).foregroundStyle(Theme.textSecondary)
            case .connecting, .creating, .joining:
                SectionLabel("Room")
                ProgressView().controlSize(.large).padding(.vertical, 8)
                Text("Connecting…").font(.subheadline).foregroundStyle(Theme.textSecondary)
            case .waiting(let info), .starting(let info):
                SectionLabel("Room code")
                Text(String(info.code))
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .tracking(6)
                HStack(spacing: 8) {
                    chip("\(info.boardSize)×\(info.boardSize) board")
                    chip(info.timer == 0 ? "No timer" : "\(info.timer)s turns")
                    if info.spectatorCount > 0 { chip("\(info.spectatorCount) watching") }
                }
                HStack(spacing: 10) {
                    Button { UIPasteboard.general.string = String(info.code) } label: { Label("Copy code", systemImage: "doc.on.doc") }
                        .buttonStyle(SecondaryButtonStyle())
                    ShareLink(item: info.inviteURL) { Label("Invite", systemImage: "square.and.arrow.up") }
                        .buttonStyle(PrimaryButtonStyle())
                }
                if info.role == .host {
                    Toggle("List in the open rooms lobby", isOn: Binding(
                        get: { info.listed },
                        set: { listed in Task { await app.online.setListed(listed) } }
                    ))
                    .font(.subheadline)
                    .padding(.top, 4)
                }
                if info.hostAway {
                    Label("The host lost connection, waiting…", systemImage: "wifi.exclamationmark")
                        .font(.footnote).foregroundStyle(Theme.warning)
                }
            case .playing:
                SectionLabel("Room")
                Text("Game in progress").font(.headline)
            case .idle, .failed:
                SectionLabel("Room")
                Text("—").font(.title)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .card()
    }

    private func seats(_ info: RoomCoordinator.RoomInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Players · \(info.seats.count) of 4")
            ForEach(info.seats) { seat in
                slot(seat, info: info)
            }
            ForEach(0..<max(0, 4 - info.seats.count), id: \.self) { index in
                emptySlot(color: PlayerPayload.defaultColors[(info.seats.count + index) % 4])
            }
            if info.role == .spectator {
                Label("The room is full, you'll get a seat next round.", systemImage: "eye")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func slot(_ seat: PlayerPayload, info: RoomCoordinator.RoomInfo) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10).fill(Color(hex: seat.colorHex)).frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(seat.displayName + (seat.id == info.mySeat ? " (you)" : "")).font(.headline)
                if seat.isCPU == true {
                    Text("Bot").font(.caption).foregroundStyle(Theme.textSecondary)
                } else if seat.id == 1 {
                    Text("Host").font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            if info.awaySeats.contains(seat.id) {
                Text("Away").font(.footnote.weight(.semibold)).foregroundStyle(Theme.warning)
            } else {
                Text("Ready").font(.footnote.weight(.semibold)).foregroundStyle(Color(hex: "#6FD99A"))
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
        .card()
    }

    private func emptySlot(color: String) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(hex: color), style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                .frame(width: 34, height: 34)
            Text("Waiting for player…").font(.subheadline).foregroundStyle(Theme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
        .card()
    }

    @ViewBuilder
    private var bottomBar: some View {
        switch app.online.state {
        case .matching:
            Button { Task { await app.online.cancelQuickMatch() } } label: { Label("Cancel", systemImage: "xmark") }
                .buttonStyle(SecondaryButtonStyle())
        case .waiting(let info) where info.role == .host:
            Button { Task { await app.online.startGame() } } label: { Label("Start Game", systemImage: "play.fill") }
                .buttonStyle(PrimaryButtonStyle(color: Theme.go))
                .disabled(info.seats.count < 2)
                .opacity(info.seats.count < 2 ? 0.5 : 1)
        case .starting:
            ProgressView("Starting…").frame(maxWidth: .infinity)
        case .waiting(let info):
            Label(info.role == .spectator ? "Waiting for the next round…" : "Waiting for the host to start…", systemImage: "hourglass")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14))
        default:
            EmptyView()
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text).font(.footnote).padding(.horizontal, 10).padding(.vertical, 5)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// `GET /matcher/open`, refreshed every 10 s while visible.
struct OpenRoomsView: View {
    @Environment(AppModel.self) private var app
    @State private var rooms: [OpenRoomDTO] = []
    @State private var error: String?
    @State private var loaded = false
    @State private var showRoom = false

    var body: some View {
        List {
            if rooms.isEmpty {
                Section {
                    ContentUnavailableView(loaded ? "No open rooms" : "Loading…", systemImage: "rectangle.stack",
                                           description: Text(error ?? (loaded ? "Create one and list it, or try Quick Match." : "")))
                }
                .listRowBackground(Theme.surface)
            }
            ForEach(rooms) { room in
                Button {
                    showRoom = true
                    Task { await app.online.join(code: room.roomCode) }
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(room.hostLabel).font(.headline)
                            Text("Room \(room.roomCode) · \(room.boardSize)×\(room.boardSize) · \(room.timer == 0 ? "no timer" : "\(room.timer)s")")
                                .font(.footnote).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Text("\(room.slotsFilled)/\(room.slotsMax)").font(.subheadline.weight(.semibold)).monospacedDigit()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Theme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle("Open rooms")
        .refreshable { await refresh() }
        .navigationDestination(isPresented: $showRoom) { WaitingRoomView() }
        .task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func refresh() async {
        do {
            rooms = try await app.backend.matcher.openRooms(boardSize: nil, timer: nil, limit: 50, offset: 0)
            error = nil
        } catch {
            self.error = RoomCoordinator.describe(error)
        }
        loaded = true
    }
}
