import SquareOffCore
import SquareOffNet
import SwiftUI

// The pieces around the board: header, turn banner, player cards, timer ring, status banner.
// Ported from the web's `components/game/screen/*` and `components/game/player/*`.

/// Phone header: Leave · room/board info · timer · Menu (web `GameHeader`, 48pt).
struct GameHeader<Session: GamePresenting>: View {
    let session: Session
    let onLeave: () -> Void
    let onMenu: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            GhostIconButton(symbol: "arrow.left", label: session.capabilities.isOnline && !session.isOver ? "Leave room" : "Back to menu", action: onLeave)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if let code = session.capabilities.roomCode {
                    HStack(spacing: 4) {
                        Text("ROOM").font(Theme.display(11, relativeTo: .caption2)).tracking(1).foregroundStyle(Theme.muted)
                        Text(String(code)).font(Theme.display(14, relativeTo: .subheadline)).tracking(1.7).monospacedDigit().foregroundStyle(Theme.foreground)
                    }
                }
                Text("\(session.game.board.size)×\(session.game.board.size)")
                    .font(Theme.display(13, relativeTo: .caption)).monospacedDigit().foregroundStyle(Theme.muted)
                if session.spectatorCount > 0 {
                    Chip(text: "\(session.spectatorCount)", symbol: "eye")
                }
            }
            Spacer(minLength: 0)
            if session.timerSeconds > 0, !session.capabilities.isSpectator {
                TimerRing(deadline: session.turnDeadline, total: session.timerSeconds, diameter: 36)
                    .padding(.trailing, 2)
            }
            GhostIconButton(symbol: "slider.horizontal.3", label: "Game menu", action: onMenu)
        }
        .padding(.horizontal, 4)
        .frame(height: 48)
        .background(Theme.overlay.opacity(0.85))
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Theme.border.frame(height: 1) }
    }
}

/// One line under the header: whose turn it is, or the room's status (web `TurnBanner`).
/// Changes are instant, like the web. The "Results" button reappears here after the game-over
/// sheet is dismissed.
struct TurnBanner<Session: GamePresenting>: View {
    @Bindable var session: Session

    var body: some View {
        let state = TurnBannerState(session: session)
        HStack(spacing: 8) {
            if state.showsEye {
                Image(systemName: "eye").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.muted)
            }
            if let dot = state.dot {
                Circle().fill(dot).frame(width: 10, height: 10)
            }
            Text(state.text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(state.foreground)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            if session.isCPUThinking, !session.isOver { ProgressView().controlSize(.mini) }
            Spacer(minLength: 0)
            if session.isOver, !session.isGameOverPresented {
                Button("Results") { session.isGameOverPresented = true }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                    .controlSize(.small)
                    .frame(height: 32)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .background(state.background)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// The banner's text and tone, in the web's priority order.
struct TurnBannerState {
    let text: String
    let background: Color
    let foreground: Color
    let dot: Color?
    let showsEye: Bool

    init<Session: GamePresenting>(session: Session) {
        let spectating = session.capabilities.isSpectator
        switch session.statusBanner {
        case .error(let message):
            self.init(text: message, background: Theme.danger.opacity(0.15), foreground: Theme.dangerText)
            return
        case .hostAway:
            self.init(text: "Host disconnected — waiting for them to reconnect…", background: Theme.warning.opacity(0.15), foreground: Theme.warning)
            return
        case .connecting:
            self.init(text: "Connecting to the game server…", background: Theme.surface, foreground: Theme.foregroundSecondary)
            return
        case nil:
            break
        }
        if session.isOver {
            let game = session.game
            let text = game.isDraw ? "Game over · Tie game" : "Game over · \(game.standings[0].name) wins"
            self.init(text: text, background: Theme.surface, foreground: Theme.foreground)
            return
        }
        if case .waitingForHost = session.rematchState {
            self.init(text: "Waiting for the host to restart…", background: Theme.surface, foreground: Theme.foregroundSecondary)
            return
        }
        if case .hostCanStart = session.rematchState {
            self.init(text: "Start the rematch when everyone's ready", background: Theme.surface, foreground: Theme.foregroundSecondary)
            return
        }
        let mover = session.currentPlayer
        let color = Color(hex: mover.colorHex)
        var text = mover.id == session.mySeatID ? "Your turn" : "\(mover.name)'s turn"
        if session.awaySeats.contains(mover.id) { text = "\(mover.name) is away…" }
        if spectating { text = "Watching live game · \(text)" }
        self.init(text: text, background: color.opacity(0.16), foreground: Theme.foreground, dot: color, showsEye: spectating)
    }

    private init(text: String, background: Color, foreground: Color, dot: Color? = nil, showsEye: Bool = false) {
        self.text = text
        self.background = background
        self.foreground = foreground
        self.dot = dot
        self.showsEye = showsEye
    }
}

/// Inline room-status alert for wide layouts and the waiting room (web `StatusBanner`).
struct StatusBannerView: View {
    let state: StatusBanner?

    var body: some View {
        switch state {
        case .connecting:
            AlertBox(.default, message: "Connecting to the game server…")
        case .hostAway:
            AlertBox(.warning, title: "Host disconnected", message: "Waiting a moment for them to reconnect…")
        case .error(let message):
            AlertBox(.danger, message: message)
        case nil:
            EmptyView()
        }
    }
}

// MARK: - Player cards

/// Colour dot, name and identity chips (web `PlayerIdentity`).
struct PlayerIdentity: View {
    let player: PlayerState
    var size: CGFloat = 10
    var isMine = false
    var isHost = false
    var nameFont: Font = .system(size: 12, weight: .semibold)

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(hex: player.colorHex))
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 2))
            Text(player.name.isEmpty ? "Player \(player.id)" : player.name)
                .font(nameFont)
                .foregroundStyle(Theme.foreground)
                .lineLimit(1)
                .truncationMode(.tail)
            if isMine { Chip(text: "You", style: .accent) }
            if player.isCPU { Chip(text: "CPU") }
            if isHost { Chip(text: "Host") }
        }
    }
}

/// Square and diamond counts (web `ShapeCounts`).
struct ShapeCounts: View {
    let player: PlayerState

    var body: some View {
        HStack(spacing: 12) {
            Label { Text("\(player.squares.count)") } icon: { Image(systemName: "square") }
            Label { Text("\(player.diamonds.count)") } icon: { Image(systemName: "diamond") }
        }
        .font(Theme.display(12, relativeTo: .caption))
        .monospacedDigit()
        .foregroundStyle(Theme.muted)
    }
}

/// "+4" / "×+1" that rises in and disappears after 1.5 s (web `ScoreDelta` + `usePlayerDeltas`).
struct ScoreDelta: View {
    let score: Int
    let multiplier: Int

    @State private var shown: (score: Int, mult: Int)?
    @State private var generation = 0

    var body: some View {
        HStack(spacing: 6) {
            if let shown {
                if shown.score > 0 {
                    Text("+\(shown.score)").foregroundStyle(Theme.success)
                }
                if shown.mult > 0 {
                    Text("×+\(shown.mult)").foregroundStyle(Theme.warning)
                }
            }
        }
        .font(Theme.display(13, relativeTo: .caption))
        .monospacedDigit()
        .id(generation)
        .transition(.offset(y: 4).combined(with: .opacity))
        .onChange(of: score) { old, new in
            guard new > old else { return }
            show(score: new - old, mult: max(0, multiplier - (shown?.mult ?? multiplier)))
        }
        .onChange(of: multiplier) { old, new in
            guard new > old else { return }
            show(score: shown?.score ?? 0, mult: new - old)
        }
        .task(id: generation) {
            guard shown != nil else { return }
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            shown = nil
        }
    }

    private func show(score: Int, mult: Int) {
        generation += 1
        withAnimation(.easeOut(duration: 0.25)) { shown = (score, mult) }
    }
}

/// A player card in one of the web's four variants.
struct PlayerCard<Trailing: View>: View {
    enum Variant: Equatable {
        /// Phone strip. `dense` when 3–4 players share the row.
        case compact(dense: Bool)
        /// Wide-layout sidebar: stat tiles and shape counts.
        case sidebar
        /// Menu / waiting room / replay row; optional seat number, no score when `showsScore` is false.
        case row(seat: Int?, showsScore: Bool)
        /// Game-over standings.
        case result(rank: Int)
    }

    let player: PlayerState
    let variant: Variant
    var isActive = false
    var isMine = false
    var isHost = false
    @ViewBuilder var trailing: Trailing

    init(player: PlayerState, variant: Variant, isActive: Bool = false, isMine: Bool = false, isHost: Bool = false,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.player = player
        self.variant = variant
        self.isActive = isActive
        self.isMine = isMine
        self.isHost = isHost
        self.trailing = trailing()
    }

    private var color: Color { Color(hex: player.colorHex) }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(isActive ? color.opacity(0.16) : (isResultWinner ? color.opacity(0.12) : Theme.surface))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(isActive || isResultWinner ? color : Theme.border, lineWidth: isActive ? 2 : 1)
            )
            .accessibilityElement(children: .combine)
    }

    private var isResultWinner: Bool {
        if case .result(let rank) = variant { return rank == 1 }
        return false
    }

    private var radius: CGFloat {
        if case .sidebar = variant { return 16 }
        return 12
    }

    @ViewBuilder
    private var content: some View {
        switch variant {
        case .compact(let dense):
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    PlayerIdentity(player: player, isMine: isMine, isHost: isHost)
                    Spacer(minLength: 0)
                    if isActive, !dense {
                        Chip(text: isMine ? "Your turn" : "Turn", style: isMine ? .accentFilled : .default)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(player.score)")
                        .font(Theme.display(dense ? 18 : 24, relativeTo: .title2))
                        .monospacedDigit()
                        .foregroundStyle(Theme.foreground)
                        .contentTransition(.numericText(value: Double(player.score)))
                        .animation(.easeOut(duration: 0.25), value: player.score)
                    Text("×\(player.multiplier)").font(.system(size: 12)).foregroundStyle(Theme.muted).monospacedDigit()
                    ScoreDelta(score: player.score, multiplier: player.multiplier)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: dense ? 56 : 64)

        case .sidebar:
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    PlayerIdentity(player: player, size: 14, isMine: isMine, isHost: isHost, nameFont: .system(size: 15, weight: .semibold))
                    if isActive { Chip(text: isMine ? "Your turn" : "Turn", style: isMine ? .accentFilled : .default) }
                    Spacer(minLength: 0)
                    trailing
                }
                HStack(spacing: 8) {
                    statTile("Score", "\(player.score)")
                    statTile("Mult", "×\(player.multiplier)")
                }
                ShapeCounts(player: player)
            }
            .padding(16)

        case .row(let seat, let showsScore):
            HStack(spacing: 12) {
                if let seat {
                    Text("\(seat)")
                        .font(Theme.display(12, relativeTo: .caption))
                        .foregroundStyle(Theme.foregroundSecondary)
                        .frame(width: 24, height: 24)
                        .background(Theme.controlFill, in: Circle())
                }
                PlayerIdentity(player: player, size: 12, isMine: isMine, isHost: isHost, nameFont: .system(size: 14, weight: .semibold))
                Spacer(minLength: 0)
                if showsScore {
                    Text("\(player.score)").font(Theme.display(17, relativeTo: .headline)).monospacedDigit().foregroundStyle(Theme.foreground)
                    Text("×\(player.multiplier)").font(.caption).foregroundStyle(Theme.muted)
                }
                trailing
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

        case .result(let rank):
            HStack(spacing: 12) {
                Group {
                    if rank == 1 {
                        Image(systemName: "crown.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.warning)
                    } else {
                        Text("\(rank)").font(Theme.display(13, relativeTo: .caption)).foregroundStyle(Theme.foregroundSecondary)
                    }
                }
                .frame(width: 28, height: 28)
                .background(Theme.controlFill, in: Circle())
                PlayerIdentity(player: player, size: 12, isMine: isMine, isHost: isHost, nameFont: .system(size: 14, weight: .semibold))
                Spacer(minLength: 0)
                ShapeCounts(player: player)
                Text("×\(player.multiplier)").font(.caption).foregroundStyle(Theme.muted)
                Text("\(player.score)")
                    .font(Theme.display(20, relativeTo: .title3))
                    .monospacedDigit()
                    .foregroundStyle(Theme.foreground)
                    .frame(minWidth: 44, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private func statTile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(Theme.display(10.5, relativeTo: .caption2)).tracking(1.2).foregroundStyle(Theme.muted)
            Text(value).font(Theme.display(24, relativeTo: .title2)).monospacedDigit().foregroundStyle(Theme.foreground)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Dashed "Spectator · watching only" row (web `SpectatorRow`).
struct SpectatorRow: View {
    var explains = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "eye").font(.system(size: 14)).foregroundStyle(Theme.muted).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                (Text("Spectator").fontWeight(.semibold) + Text(" · watching only"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                if explains {
                    Text("Joins the next round when the host restarts").font(.caption).foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }
}

/// The phone card strip: 2 columns, or 4 dense cards for 3–4 players (web `PlayerCards`).
struct PlayerStrip<Session: GamePresenting>: View {
    let session: Session

    var body: some View {
        let players = session.game.players
        let dense = players.count > 2
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: players.count), spacing: 8) {
            ForEach(players) { player in
                PlayerCard(
                    player: player,
                    variant: .compact(dense: dense),
                    isActive: player.id == session.currentPlayer.id && !session.isOver,
                    isMine: player.id == session.mySeatID,
                    isHost: session.capabilities.isOnline && player.id == 1
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Timer

/// Depleting ring with the seconds left in the middle (web `TurnTimer`). Accent above half,
/// warning above a fifth, danger below. Driven per frame from the deadline.
struct TimerRing: View {
    let deadline: Date?
    let total: Int
    let diameter: CGFloat

    var body: some View {
        TimelineView(.animation(paused: deadline == nil)) { context in
            let remaining = max(0, (deadline ?? context.date).timeIntervalSince(context.date))
            let fraction = total > 0 ? min(1, remaining / Double(total)) : 0
            let seconds = Int(remaining.rounded(.up))
            let stroke = max(3, (diameter * 7 / 80).rounded())
            ZStack {
                Circle().stroke(Theme.border, lineWidth: stroke)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(color(for: fraction), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(deadline == nil ? total : seconds)")
                    .font(Theme.display(max(12, (diameter * 0.32).rounded()), relativeTo: .caption))
                    .monospacedDigit()
                    .foregroundStyle(Theme.foreground)
            }
            .frame(width: diameter, height: diameter)
        }
        .accessibilityLabel("Turn timer")
    }

    private func color(for fraction: Double) -> Color {
        if fraction > 0.5 { return Theme.accent }
        if fraction > 0.2 { return Theme.warning }
        return Theme.danger
    }
}
