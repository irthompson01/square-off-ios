import SquareOffCore
import SwiftUI

/// Full-screen game. iPhone and iPad portrait stack vertically; iPad landscape puts the board
/// on the left with a sidebar, like the web's md+ layout.
struct GameView: View {
    @Environment(AppModel.self) private var app
    @Bindable var session: GameSession
    @State private var isMenuPresented = false
    @State private var confirmLeave = false
    /// Set when "leave" is tapped inside a sheet: the cover is dismissed only after the sheet
    /// has gone, because dismissing both in one transaction drops the outer one.
    @State private var pendingLeave = false

    var body: some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width > proxy.size.height && proxy.size.width > 700
            Group {
                if landscape {
                    HStack(alignment: .top, spacing: 32) {
                        BoardView(session: session, gap: 6)
                            .frame(maxHeight: .infinity)
                        sidebar
                            .frame(width: 340)
                    }
                    .padding(32)
                } else {
                    VStack(spacing: 12) {
                        header
                        PlayerStrip(session: session)
                        turnBanner
                        BoardView(session: session, gap: proxy.size.width > 600 ? 6 : 4)
                        lastMovePill
                        Spacer(minLength: 0)
                        controls
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                }
            }
        }
        .appBackground()
        .overlay(alignment: .top) { noticeBanner }
        .task { await session.start() }
        .onDisappear { session.stop() }
        .sheet(isPresented: $isMenuPresented, onDismiss: finishLeaveIfPending) {
            GameMenuSheet(session: session, onLeave: leave)
                .presentationDetents([.medium, .large])
                .presentationBackground(Theme.surface)
        }
        .sheet(isPresented: $session.isGameOverPresented, onDismiss: finishLeaveIfPending) {
            GameOverSheet(session: session, onHome: leave)
                .presentationDetents([.large])
                .presentationBackground(Theme.surface)
        }
        .confirmationDialog("Leave this game?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave game", role: .destructive, action: leave)
        } message: {
            Text("Your progress in this game will be lost.")
        }
    }

    /// Leaves the game and returns to the menu. Safe to call from inside a sheet.
    private func leave() {
        session.stop()
        if isMenuPresented || session.isGameOverPresented {
            pendingLeave = true
            isMenuPresented = false
            session.isGameOverPresented = false
        } else {
            app.isGamePresented = false
        }
    }

    private func finishLeaveIfPending() {
        guard pendingLeave else { return }
        pendingLeave = false
        app.isGamePresented = false
    }

    private func closeTapped() {
        if session.isOver { leave() } else { confirmLeave = true }
    }

    private var closeButton: some View {
        Button(action: closeTapped) {
            Image(systemName: "xmark").font(.subheadline.weight(.bold)).frame(width: 36, height: 36)
        }
        .background(Theme.surfaceRaised, in: Circle())
        .accessibilityLabel(session.isOver ? "Back to menu" : "Leave game")
    }

    // MARK: Pieces

    private var header: some View {
        HStack {
            Text(session.config.title)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            TimerChip(remaining: session.timeRemaining, enabled: session.config.timerSeconds > 0)
            closeButton
        }
        .frame(minHeight: 36)
    }

    private var turnBanner: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: session.currentPlayer.colorHex))
                .frame(width: 12, height: 12)
            Text(session.turnLabel)
                .font(.headline)
                .contentTransition(.opacity)
            if session.isCPUThinking { ProgressView().controlSize(.small) }
        }
        .frame(height: 32)
        .animation(.easeOut(duration: 0.2), value: session.turnLabel)
    }

    @ViewBuilder
    private var lastMovePill: some View {
        if let move = session.lastMove, move.newShapeCount > 0,
           let mover = session.game.players.first(where: { $0.id == move.playerID }) {
            HStack(spacing: 8) {
                Text("+\(move.scoreIncrease)").bold()
                Text(describe(move, by: mover)).foregroundStyle(.white.opacity(0.85))
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .card(tint: Color(hex: mover.colorHex))
            .transition(.scale.combined(with: .opacity))
            .id(session.placeCount)
        } else {
            Color.clear.frame(height: 34)
        }
    }

    private func describe(_ move: MoveResult, by player: PlayerState) -> String {
        let shapes = move.newShapes
        let what: String
        if shapes.count == 1, let shape = shapes.first {
            what = "a \(shape.size)×\(shape.size) \(shape.kind.rawValue)"
        } else {
            what = "\(shapes.count) shapes ×\(move.multiplierAfter)"
        }
        return "\(player.name) formed \(what)"
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 10) {
            if session.isOver {
                Button { session.restart() } label: {
                    Label("Rematch", systemImage: "arrow.counterclockwise")
                }
                Button { session.isGameOverPresented = true } label: {
                    Label("Results", systemImage: "trophy")
                }
                Button(action: leave) {
                    Label("Home", systemImage: "house")
                }
            } else {
                Button {
                    let everyone = Set(session.game.players.map(\.id))
                    session.hiddenShapeOwners = session.hiddenShapeOwners.isEmpty ? everyone : []
                } label: {
                    Label(session.hiddenShapeOwners.isEmpty ? "Shapes on" : "Shapes off", systemImage: "eye")
                }
                Button { session.isGameOverPresented = true } label: {
                    Label("Stats", systemImage: "chart.line.uptrend.xyaxis")
                }
                Button { isMenuPresented = true } label: {
                    Label("Menu", systemImage: "line.3.horizontal")
                }
            }
        }
        .buttonStyle(SecondaryButtonStyle())
        .labelStyle(.titleAndIcon)
        .animation(.easeOut(duration: 0.2), value: session.isOver)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(session.config.title).font(.subheadline).foregroundStyle(Theme.textSecondary)
                Spacer()
                Button { isMenuPresented = true } label: {
                    Image(systemName: "line.3.horizontal").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Game menu")
                .background(Theme.surfaceRaised, in: Circle())
                closeButton
            }
            HStack {
                turnBanner
                Spacer()
                TimerChip(remaining: session.timeRemaining, enabled: session.config.timerSeconds > 0)
            }
            .padding(14)
            .card()
            ForEach(session.game.players) { player in
                PlayerCard(player: player, isActive: player.id == session.currentPlayer.id && !session.isOver, compact: false)
            }
            ScoreChart(players: session.game.players)
                .frame(maxHeight: .infinity)
                .padding(14)
                .card()
            lastMovePill
            controls
        }
    }

    @ViewBuilder
    private var noticeBanner: some View {
        if let notice = session.notice {
            Text(notice)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.warning.opacity(0.9), in: Capsule())
                .foregroundStyle(.black)
                .padding(.top, 4)
                .onTapGesture { session.notice = nil }
                .task {
                    try? await Task.sleep(for: .seconds(4))
                    session.notice = nil
                }
        }
    }
}

struct PlayerStrip: View {
    let session: GameSession

    var body: some View {
        let players = session.game.players
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: players.count), spacing: 10) {
            ForEach(players) { player in
                PlayerCard(player: player, isActive: player.id == session.currentPlayer.id && !session.isOver, compact: players.count > 2)
            }
        }
    }
}

struct PlayerCard: View {
    let player: PlayerState
    let isActive: Bool
    var compact: Bool

    var body: some View {
        let color = Color(hex: player.colorHex)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
                Text(player.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
                Text("×\(player.multiplier)")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(player.score)")
                    .font(.system(size: compact ? 22 : 28, weight: .heavy))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(player.score)))
                if !compact {
                    Text("pts · \(player.shapeCount) shapes").font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isActive ? color.opacity(0.16) : Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isActive ? color : Color.white.opacity(0.06), lineWidth: 2)
        )
        .animation(.easeOut(duration: 0.25), value: player.score)
        .animation(.easeOut(duration: 0.2), value: isActive)
    }
}

struct TimerChip: View {
    let remaining: Int?
    let enabled: Bool

    var body: some View {
        if enabled {
            Label("0:\(String(format: "%02d", remaining ?? 0))", systemImage: "timer")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle((remaining ?? 99) <= 5 ? Theme.destructive : Theme.warning)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Theme.surfaceRaised, in: Capsule())
        }
    }
}
