import SquareOffCore
import SwiftUI

/// The Play page (web `/setup`): mode switch, shared settings, players editor, the Online
/// panel and one sticky primary action.
struct PlayView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss
    @State private var setup: PlaySetupModel

    init(mode: PlaySetupModel.Mode = .cpu, onlineTab: PlaySetupModel.OnlineTab = .create) {
        let setup = PlaySetupModel()
        setup.mode = mode
        setup.onlineTab = onlineTab
        _setup = State(initialValue: setup)
    }
    @State private var isPending = false
    @State private var showRoom = false
    @State private var debugColorSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                BackButton(title: "Home") { dismiss() }
                PageHeading(title: "Play", description: "Pick a mode, set the board, go.")
                if let session = app.activeGame, !session.isOver {
                    ContinueGameCard(session: session)
                }
                SegmentedPills(options: PlaySetupModel.Mode.allCases, selection: $setup.mode, title: \.title, symbol: \.symbol, compact: sizeClass != .regular)
                settings
                playersEditor
                if setup.mode == .online {
                    OnlinePanel(setup: setup, onJoinRoom: { openRoom() })
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .appBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { stickyBar }
        .navigationDestination(isPresented: $showRoom) { WaitingRoomView() }
        .task(id: app.account) { setup.prefill(from: app.account) }
        .onChange(of: app.online.state) { _, state in
            switch state {
            case .connecting, .creating, .joining, .waiting, .starting:
                if !showRoom { openRoom() }
                isPending = false
            case .failed(let error):
                isPending = false
                if !showRoom {
                    app.toasts.danger(setup.onlineTab == .quick ? "Quick match failed" : "Couldn't create the room", description: error.message) {
                        Task { await primaryAction() }
                    }
                }
            case .idle, .matching, .playing:
                isPending = false
            }
        }
        .onAppear(perform: handlePendingRoutes)
        .sheet(isPresented: $debugColorSheet) {
            ColorSwatchSheet(selection: $setup.players[0].colorHex)
                .presentationDetents([.height(260)])
                .presentationBackground(Theme.overlay)
        }
    }

    // MARK: Sections

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Game settings")
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    SettingStepper(title: "Board", selection: $setup.boardSize, options: PlaySetupModel.boardSizes) { "\($0) × \($0)" }
                    SettingStepper(title: "Timer", selection: $setup.timer, options: PlaySetupModel.timers) { $0 == 0 ? "No timer" : "\($0) sec" }
                }
                if setup.mode == .cpu {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CPU level").font(.subheadline.weight(.medium)).foregroundStyle(Theme.foreground)
                        LevelPicker(selection: $setup.level, unavailable: CPUAvailability.unavailableLevels(boardSize: setup.boardSize))
                        if let description = setup.level.description {
                            Text(description).font(.caption).foregroundStyle(Theme.foregroundSecondary)
                        }
                        Label(CPUAvailability.footnote(kind: app.backend.configuration.kind, level: setup.level), systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }
                if setup.mode == .local {
                    SettingSegments(title: "Players", selection: $setup.playerCount, options: [2, 3, 4]) { "\($0) players" }
                }
            }
            .padding(14)
            .card()
        }
        .onChange(of: setup.boardSize) { _, _ in
            if !CPUAvailability.isSelectable(setup.level, boardSize: setup.boardSize) { setup.level = .random }
        }
    }

    private var playersEditor: some View {
        let signedIn = app.account.isSignedIn
        let single = setup.visibleSeatCount == 1
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(single ? (signedIn ? "Your profile" : "Your name") : "Players")
            VStack(alignment: .leading, spacing: 14) {
                ForEach(0..<setup.visibleSeatCount, id: \.self) { index in
                    let isYou = index == 0 && signedIn
                    HStack(alignment: .bottom, spacing: 12) {
                        LabeledField(label: isYou ? "You" : "Player \(index + 1)",
                                     help: isYou ? "From your profile. Edits here apply to this game only." : nil) {
                            TextField("Player \(index + 1)", text: Binding(
                                get: { setup.players[index].name },
                                set: { setup.setName($0, forSeat: index) }
                            ))
                            .textInputAutocapitalization(.words)
                            .foregroundStyle(Theme.foreground)
                        }
                        ColorSwatchPicker(selection: $setup.players[index].colorHex)
                            .padding(.bottom, isYou ? 22 : 2)
                    }
                }
                if let warning = setup.duplicateColorWarning {
                    Text(warning).font(.caption).foregroundStyle(Theme.warning)
                }
            }
            .padding(14)
            .card()
        }
    }

    @ViewBuilder
    private var stickyBar: some View {
        if let title = setup.primaryTitle, !isSearching {
            HStack {
                if sizeClass == .regular { Spacer() }
                Button {
                    Task { await primaryAction() }
                } label: {
                    PendingLabel(title: title, pendingTitle: setup.pendingTitle, symbol: setup.primarySymbol, isPending: isPending)
                }
                .buttonStyle(PrimaryButtonStyle(large: true, fullWidth: sizeClass != .regular))
                .frame(minWidth: sizeClass == .regular ? 224 : nil)
                .disabled(isPending || (setup.mode == .online && setup.onlineTab == .join && !setup.isJoinCodeValid))
                .opacity(setup.mode == .online && setup.onlineTab == .join && !setup.isJoinCodeValid ? 0.5 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(Theme.background.opacity(0.85))
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) { Theme.border.frame(height: 1) }
        }
    }

    private var isSearching: Bool {
        if case .matching = app.online.state { return true }
        return false
    }

    // MARK: Actions

    private func primaryAction() async {
        if let seat = setup.resolvedPlayers.first { app.online.seatPreference = (seat.name, seat.colorHex) }
        switch setup.mode {
        case .cpu, .local:
            app.start(setup.gameConfig())
        case .online:
            switch setup.onlineTab {
            case .create:
                isPending = true
                await app.online.host(boardSize: setup.boardSize, timer: setup.timer, listPublic: setup.listPublic)
            case .quick:
                await app.online.quickMatch(boardSize: setup.boardSize, timer: setup.timer)
            case .join:
                guard setup.isJoinCodeValid, let code = Int(setup.joinCode) else { return }
                isPending = true
                await app.online.join(code: code)
            case .rooms:
                break
            }
        }
    }

    private func openRoom() {
        showRoom = true
    }

    private func handlePendingRoutes() {
        app.online.refreshRejoinable()
        if let code = app.pendingJoinCode {
            app.pendingJoinCode = nil
            setup.mode = .online
            setup.onlineTab = .join
            setup.joinCode = String(code)
            isPending = true
            Task { await app.online.join(code: code) }
        }
        if app.pendingOnlineRoom {
            app.pendingOnlineRoom = false
            setup.mode = .online
            openRoom()
        }
        if app.pendingColorPicker {
            app.pendingColorPicker = false
            debugColorSheet = true
        }
    }
}

/// "Continue game" card on Home and Play (web `ResumeGameCard`).
struct ContinueGameCard: View {
    @Environment(AppModel.self) private var app
    let session: GameSession

    var body: some View {
        let players = session.game.players
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel("Continue game")
                Spacer()
                if let savedAt = session.savedAt {
                    Text(RelativeAgo.coarse(savedAt)).font(.caption).foregroundStyle(Theme.muted)
                }
            }
            HStack(spacing: 6) {
                ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                    if index > 0 { Text("vs").font(.caption).foregroundStyle(Theme.muted) }
                    Circle().fill(Color(hex: player.colorHex)).frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 2))
                    Text(player.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.foreground).lineLimit(1)
                }
                Text("·").foregroundStyle(Theme.muted)
                Text("\(session.game.board.size)×\(session.game.board.size)").font(Theme.display(14, relativeTo: .subheadline)).monospacedDigit().foregroundStyle(Theme.foreground)
                Text("·").foregroundStyle(Theme.muted)
                Text("\(session.currentPlayer.name)'s turn").font(.subheadline).foregroundStyle(Theme.foregroundSecondary).lineLimit(1)
            }
            .minimumScaleFactor(0.8)
            HStack(spacing: 8) {
                Button { app.resumeGame() } label: { Label("Resume", systemImage: "play.fill") }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                Button { app.discardGame() } label: { Label("Discard", systemImage: "trash") }
                    .buttonStyle(TertiaryButtonStyle(fullWidth: false))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Continue game")
    }
}
