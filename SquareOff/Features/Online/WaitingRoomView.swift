import SquareOffCore
import SquareOffNet
import SwiftUI

/// The lobby of one room, driven by `RoomCoordinator.state` (web `WaitingRoom`). Pops itself
/// when the coordinator goes idle; a fatal error replaces the room with an alert.
struct WaitingRoomView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var confirmLeave = false
    @State private var copied = false
    @State private var startWatchdog: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if case .failed(let error) = app.online.state {
                    fatal(error)
                } else {
                    room
                }
            }
            .padding(16)
            .frame(maxWidth: 576)
            .frame(maxWidth: .infinity)
        }
        .appBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(true)
        .onChange(of: app.online.state) { _, state in
            if case .idle = state { dismiss() }
            if case .playing = state { startWatchdog?.cancel() }
        }
        .alert("Leave this room?", isPresented: $confirmLeave) {
            Button("Leave room", role: .destructive) { Task { await app.online.leave() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(app.online.state.roomInfo?.role == .host ? "The room closes for everyone when the host leaves." : "You will exit to the setup screen.")
        }
    }

    private var title: String {
        switch app.online.state {
        case .connecting, .creating, .joining: "Connecting"
        default: "Room"
        }
    }

    // MARK: Room

    @ViewBuilder
    private var room: some View {
        let info = app.online.state.roomInfo
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(heading(info)).font(Theme.display(22, relativeTo: .title2)).foregroundStyle(Theme.foreground)
                    Text(subtitle(info)).font(.subheadline).foregroundStyle(Theme.foregroundSecondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                connectionChip(info)
            }
            StatusBannerView(state: banner(info))

            VStack(spacing: 10) {
                SectionLabel("Room code")
                if let info {
                    Text(String(info.code))
                        .font(Theme.display(48, relativeTo: .largeTitle))
                        .tracking(9)
                        .monospacedDigit()
                        .foregroundStyle(Theme.foreground)
                } else {
                    SkeletonBar(width: 160, height: 48)
                }
                HStack(spacing: 10) {
                    Button {
                        guard let info else { return }
                        UIPasteboard.general.string = info.inviteURL.absoluteString
                        app.toasts.success("Invite link copied")
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    } label: {
                        Label(copied ? "Copied" : "Copy invite link", systemImage: copied ? "checkmark" : "link")
                            .foregroundStyle(copied ? Theme.success : Theme.foreground)
                    }
                    .buttonStyle(SecondaryButtonStyle(fullWidth: false))
                    .disabled(info == nil)
                    if let info {
                        ShareLink(item: info.inviteURL, subject: Text("Join my Square Off game"), message: Text("Room \(info.code)")) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(SecondaryButtonStyle(fullWidth: false))
                    }
                }
            }
            .frame(maxWidth: .infinity)

            if let info {
                HStack(spacing: 8) {
                    Chip(text: "\(info.boardSize)×\(info.boardSize)")
                    Chip(text: info.timer == 0 ? "No timer" : "\(info.timer) seconds per turn")
                    Spacer()
                }
                if info.role == .host {
                    SettingsToggle(title: "List in public lobby", description: "Anyone can find and join this room from Setup.", isOn: Binding(
                        get: { info.listed },
                        set: { listed in Task { await app.online.setListed(listed) } }
                    ))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .card(fill: Theme.surfaceSecondary, radius: 12)
                }
                seats(info)
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Connecting…").font(.subheadline).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity)
            }

            footer(info)
        }
        .padding(20)
        .card()
    }

    private func heading(_ info: RoomCoordinator.RoomInfo?) -> String {
        switch info?.role {
        case .guest: "Waiting for the host"
        case .spectator: "Spectating"
        default: "Waiting for players"
        }
    }

    private func subtitle(_ info: RoomCoordinator.RoomInfo?) -> String {
        switch info?.role {
        case .guest: "The host starts the game once everyone's in."
        case .spectator: "You're watching this room. If the host restarts, you'll get a seat next round."
        default: (info?.seats.count ?? 0) < 2 ? "Share the code or link. The game starts when you're ready." : "Everyone can still join until you start."
        }
    }

    private func connectionChip(_ info: RoomCoordinator.RoomInfo?) -> some View {
        Group {
            if info == nil {
                Chip(text: "Connecting…", dot: true)
            } else if info?.hostAway == true {
                Chip(text: "Host away", style: .warning, dot: true)
            } else {
                Chip(text: "Connected", style: .success, dot: true)
            }
        }
    }

    private func banner(_ info: RoomCoordinator.RoomInfo?) -> StatusBanner? {
        if info?.hostAway == true { return .hostAway }
        if info == nil, case .joining = app.online.state { return .connecting }
        return nil
    }

    private func seats(_ info: RoomCoordinator.RoomInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Players")
                Spacer()
                Text("\(info.seats.count)/4").font(Theme.display(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
                    .accessibilityLabel("Seats filled: \(info.seats.count) of 4")
            }
            ForEach(Array(info.seats.enumerated()), id: \.element.id) { index, seat in
                PlayerCard(player: seat.playerState, variant: .row(seat: index + 1, showsScore: false),
                           isMine: seat.id == info.mySeat, isHost: seat.id == 1) {
                    if seat.isCPU == true { Chip(text: "Bot") }
                    if info.awaySeats.contains(seat.id) { Chip(text: "Away", style: .warning) }
                }
            }
            ForEach(0..<max(0, 4 - info.seats.count), id: \.self) { index in
                HStack(spacing: 12) {
                    Circle().strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(width: 24, height: 24)
                    if index == 0 {
                        Text("Waiting for a player…").font(.subheadline).foregroundStyle(Theme.muted)
                        ProgressView().controlSize(.mini)
                    } else {
                        Text("Open seat").font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            }
            if info.spectatorCount > 0 {
                SectionLabel("Spectators · \(info.spectatorCount)").padding(.top, 6)
                ForEach(0..<info.spectatorCount, id: \.self) { index in
                    SpectatorRow(explains: index == 0 && info.role == .host)
                }
            }
        }
    }

    @ViewBuilder
    private func footer(_ info: RoomCoordinator.RoomInfo?) -> some View {
        let starting: Bool = { if case .starting = app.online.state { return true } else { return false } }()
        VStack(spacing: 10) {
            if let info, info.role == .host {
                Button {
                    startGame()
                } label: {
                    PendingLabel(title: "Start game", pendingTitle: "Starting…", symbol: "play.fill", isPending: starting)
                }
                .buttonStyle(PrimaryButtonStyle(large: true))
                .disabled(info.seats.count < 2 || starting)
                .opacity(info.seats.count < 2 ? 0.5 : 1)
                if info.seats.count < 2 {
                    Text("Needs at least 2 players").font(.caption).foregroundStyle(Theme.muted)
                }
            }
            Button { confirmLeave = true } label: { Label("Leave room", systemImage: "rectangle.portrait.and.arrow.right") }
                .buttonStyle(TertiaryButtonStyle())
        }
        .padding(.top, 4)
    }

    private func startGame() {
        startWatchdog?.cancel()
        startWatchdog = Task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            if case .starting = app.online.state {
                app.toasts.show("Still waiting for the server…", description: "Try starting the game again.", style: .warning)
            }
        }
        Task { await app.online.startGame() }
    }

    private func fatal(_ error: RoomCoordinator.OnlineError) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            AlertBox(.danger, title: app.online.lastRole == .host ? "The room is unavailable" : "Can't join this room", message: error.message)
            Button("Back to setup") { Task { await app.online.leave() } }
                .buttonStyle(SecondaryButtonStyle(small: true, fullWidth: false))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

extension PlayerPayload {
    /// A seat as a `PlayerState` for the shared card views (scores shown only once the game runs).
    var playerState: PlayerState {
        PlayerState(id: id, name: displayName, colorHex: colorHex, isCPU: isCPU ?? false)
    }
}
