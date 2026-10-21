import SquareOffCore
import SwiftUI

/// Full-screen game (web `GameScreen`). Phones stack header → turn banner → player cards →
/// board; wide layouts put a sidebar on the left and the timer in its own column on the right.
struct GameView<Session: GamePresenting>: View {
    @Environment(AppModel.self) private var app
    @Bindable var session: Session
    @State private var isMenuPresented = false
    @State private var confirmLeave = false
    @State private var confirmReset = false
    @State private var isRulesPresented = false
    /// Set when "leave" is tapped inside a sheet: the cover is dismissed only after the sheet
    /// has gone, because dismissing both in one transaction drops the outer one.
    @State private var pendingExit: AppModel.GameExit?

    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width >= 700
            Group {
                if wide {
                    HStack(spacing: 0) {
                        sidebar.frame(width: proxy.size.width >= 1024 ? 416 : 352)
                        Theme.border.frame(width: 1)
                        BoardView(session: session)
                            .padding(24)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if session.timerSeconds > 0, !session.capabilities.isSpectator {
                            VStack {
                                TimerRing(deadline: session.turnDeadline, total: session.timerSeconds, diameter: 96)
                                    .padding(.top, 24)
                                Spacer()
                            }
                            .frame(width: 112)
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        GameHeader(session: session, onLeave: closeTapped, onMenu: { isMenuPresented = true })
                        TurnBanner(session: session)
                        PlayerStrip(session: session)
                        BoardView(session: session)
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .appBackground()
        .overlay(alignment: .top) { noticeBanner }
        .task { await session.start() }
        .onDisappear { session.stop() }
        .onChange(of: session.isOver) { _, over in
            if over { confirmReset = false }
        }
        .sheet(isPresented: $isMenuPresented, onDismiss: finishExitIfPending) {
            GameMenuSheet(session: session, onReset: { confirmReset = true }, onLeave: { confirmLeave = true }, onRules: { isRulesPresented = true })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.overlay)
        }
        .sheet(isPresented: $session.isGameOverPresented, onDismiss: finishExitIfPending) {
            GameOverSheet(session: session, onExit: exit)
                .presentationDetents([.large])
                .presentationBackground(Theme.overlay)
        }
        .sheet(isPresented: $isRulesPresented) {
            NavigationStack { RulesView() }
                .presentationBackground(Theme.background)
        }
        .alert(session.capabilities.isOnline ? "Leave this room?" : "Leave this game?", isPresented: $confirmLeave) {
            Button(session.capabilities.isOnline ? "Leave room" : "Leave game", role: .destructive) { exit(.setup) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(session.role == .host ? "The room closes for everyone when the host leaves." : "You will exit to the setup screen.")
        }
        .alert("Reset this game?", isPresented: $confirmReset) {
            Button("Reset game", role: .destructive) { session.restart() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The board and scores will be cleared. This cannot be undone.")
        }
    }

    // MARK: Leaving

    /// Leaves the game and returns to the menu. Safe to call from inside a sheet.
    private func exit(_ destination: AppModel.GameExit) {
        session.leave()
        if isMenuPresented || session.isGameOverPresented {
            pendingExit = destination
            isMenuPresented = false
            session.isGameOverPresented = false
        } else {
            app.exitGame(to: destination)
        }
    }

    private func finishExitIfPending() {
        guard let destination = pendingExit else { return }
        pendingExit = nil
        app.exitGame(to: destination)
    }

    /// Header arrow: a local game goes back to the menu and stays available on the Continue
    /// card; an online room asks before leaving (the seat is lost).
    private func closeTapped() {
        if session.isOver || session.capabilities.isSpectator || session.statusBanner.isFatal {
            exit(.setup)
        } else if session.capabilities.isOnline {
            isMenuPresented = false
            confirmLeave = true
        } else {
            session.stop()
            app.minimizeGame()
        }
    }

    // MARK: Wide layout

    private var sidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let code = session.capabilities.roomCode {
                        VStack(alignment: .leading, spacing: 4) {
                            SectionLabel("Room code")
                            Text(String(code)).font(Theme.display(22, relativeTo: .title2)).tracking(2.5).monospacedDigit().foregroundStyle(Theme.foreground)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                    }
                    StatusBannerView(state: session.statusBanner)
                    if session.capabilities.isSpectator {
                        AlertBox(.accent, title: "Watching live game", message: "You'll join the next round when the host restarts.")
                    }
                    ForEach(session.game.players) { player in
                        PlayerCard(
                            player: player,
                            variant: .sidebar,
                            isActive: player.id == session.currentPlayer.id && !session.isOver,
                            isMine: player.id == session.mySeatID,
                            isHost: session.capabilities.isOnline && player.id == 1
                        ) {
                            let hidden = session.hiddenShapeOwners.contains(player.id)
                            GhostIconButton(symbol: hidden ? "eye.slash" : "eye", label: "\(hidden ? "Show" : "Hide") \(player.name)'s shapes", size: 32) {
                                toggleShapes(for: player.id)
                            }
                        }
                    }
                    if session.spectatorCount > 0 {
                        SectionLabel("Spectators · \(session.spectatorCount)").padding(.top, 4)
                        ForEach(0..<session.spectatorCount, id: \.self) { index in
                            SpectatorRow(explains: index == 0)
                        }
                    }
                    ScoreChart(players: session.game.players)
                        .frame(height: 180)
                        .padding(14)
                        .card()
                }
                .padding(16)
            }
            Theme.border.frame(height: 1)
            HStack(spacing: 8) {
                if session.isOver, !session.isGameOverPresented {
                    Button("Results") { session.isGameOverPresented = true }
                        .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                }
                if session.capabilities.canReset, !session.isOver {
                    Button { confirmReset = true } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
                        .buttonStyle(SecondaryButtonStyle(small: true, fullWidth: false))
                }
                Button { closeTapped() } label: { Label("Leave", systemImage: "rectangle.portrait.and.arrow.right") }
                    .buttonStyle(DangerButtonStyle(soft: true, small: true, fullWidth: false))
                Spacer()
                GhostIconButton(symbol: "slider.horizontal.3", label: "Game menu") { isMenuPresented = true }
            }
            .padding(12)
        }
        .background(Theme.overlay.opacity(0.6))
    }

    private func toggleShapes(for owner: Int) {
        if session.hiddenShapeOwners.contains(owner) {
            session.hiddenShapeOwners.remove(owner)
        } else {
            session.hiddenShapeOwners.insert(owner)
        }
    }

    @ViewBuilder
    private var noticeBanner: some View {
        if let notice = session.notice {
            Text(notice)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.warning.opacity(0.95), in: Capsule())
                .foregroundStyle(Theme.background)
                .padding(.top, 56)
                .onTapGesture { session.notice = nil }
                .task {
                    try? await Task.sleep(for: .seconds(4))
                    session.notice = nil
                }
        }
    }
}

private extension Optional where Wrapped == StatusBanner {
    var isFatal: Bool {
        if case .error = self { return true }
        return false
    }
}
