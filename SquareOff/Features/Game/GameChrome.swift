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
            let leaving = session.capabilities.isOnline && !session.isOver
            BackButton(title: leaving ? "Leave" : "Back", accessibilityLabel: leaving ? "Leave room" : "Back to menu", action: onLeave)
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
        .padding(.leading, 12)
        .padding(.trailing, 4)
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
            if session.statusBanner == .lost {
                Button("Reconnect") { session.reconnect() }
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
    /// Plain "X's turn" with nothing else to say: the phone's player cards carry it instead.
    let isPlainTurn: Bool

    init<Session: GamePresenting>(session: Session) {
        let spectating = session.capabilities.isSpectator
        switch session.statusBanner {
        case .error(let message):
            self.init(text: message, background: Theme.danger.opacity(0.15), foreground: Theme.dangerText)
            return
        case .lost:
            self.init(text: "Connection lost", background: Theme.danger.opacity(0.15), foreground: Theme.dangerText)
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
        let away = session.awaySeats.contains(mover.id)
        var text = mover.id == session.mySeatID ? "Your turn" : "\(mover.name)'s turn"
        if away { text = "\(mover.name) is away…" }
        if spectating { text = "Watching live game · \(text)" }
        self.init(text: text, background: color.opacity(0.16), foreground: Theme.foreground, dot: color, showsEye: spectating,
                  isPlainTurn: !away && !spectating)
    }

    private init(text: String, background: Color, foreground: Color, dot: Color? = nil, showsEye: Bool = false, isPlainTurn: Bool = false) {
        self.text = text
        self.background = background
        self.foreground = foreground
        self.dot = dot
        self.showsEye = showsEye
        self.isPlainTurn = isPlainTurn
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
        case .lost:
            AlertBox(.danger, title: "Connection lost", message: "The room couldn't be reached. Reconnect, or leave the room.")
        case .error(let message):
            AlertBox(.danger, message: message)
        case nil:
            EmptyView()
        }
    }
}

// MARK: - Player cards

/// Colour disc with the player's initial, or a chip glyph for a CPU seat.
struct PlayerAvatar: View {
    let player: PlayerState
    var size: CGFloat = 26

    var body: some View {
        let color = Color(hex: player.colorHex)
        ZStack {
            Circle().fill(color)
            if player.isCPU {
                Image(systemName: "cpu").font(.system(size: (size * 0.46).rounded(), weight: .bold))
            } else {
                Text(initial).font(Theme.display((size * 0.5).rounded(), relativeTo: .caption))
            }
        }
        .foregroundStyle(Color.isLight(hex: player.colorHex) ? Color.black.opacity(0.78) : .white)
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
        .accessibilityHidden(true)
    }

    private var initial: String {
        let name = player.name.trimmingCharacters(in: .whitespaces)
        return name.first.map { String($0).uppercased() } ?? "\(player.id)"
    }
}

/// "×1" in grey, "×2"+ lit amber: the multiplier next to a score.
struct MultiplierPill: View {
    let multiplier: Int

    var body: some View {
        let boosted = multiplier > 1
        Text("×\(multiplier)")
            .font(Theme.display(12, relativeTo: .caption2))
            .monospacedDigit()
            .foregroundStyle(boosted ? Theme.warning : Theme.muted)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(boosted ? Theme.warning.opacity(0.16) : Theme.controlFill, in: Capsule())
            .contentTransition(.numericText(value: Double(multiplier)))
            .animation(.easeOut(duration: 0.25), value: multiplier)
            .accessibilityLabel("Multiplier ×\(multiplier)")
    }
}

/// Small "You" / "Host" tag for the phone cards, where a full chip would crowd the row.
private struct SeatTag: View {
    let text: String
    var color: Color = Theme.foregroundSecondary

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(color.opacity(0.14), in: Capsule())
            .fixedSize()
    }
}

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
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: size) {
            Label { Text("\(player.squares.count)") } icon: { Image(systemName: "square") }
            Label { Text("\(player.diamonds.count)") } icon: { Image(systemName: "diamond") }
        }
        .font(Theme.display(size, relativeTo: .caption))
        .monospacedDigit()
        .foregroundStyle(Theme.muted)
        .accessibilityLabel("\(player.squares.count) squares, \(player.diamonds.count) diamonds")
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
    /// The CPU in this seat is choosing a move (phone cards show it in the turn pill).
    var isThinking = false
    @ViewBuilder var trailing: Trailing

    init(player: PlayerState, variant: Variant, isActive: Bool = false, isMine: Bool = false, isHost: Bool = false,
         isThinking: Bool = false, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.player = player
        self.variant = variant
        self.isActive = isActive
        self.isMine = isMine
        self.isHost = isHost
        self.isThinking = isThinking
        self.trailing = trailing()
    }

    private var color: Color { Color(hex: player.colorHex) }

    private var isCompact: Bool {
        if case .compact = variant { return true }
        return false
    }

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
            .shadow(color: isCompact && isActive ? color.opacity(0.35) : .clear, radius: 12, y: 2)
            .animation(.easeOut(duration: 0.25), value: isActive)
            .accessibilityElement(children: .combine)
            .accessibilityValue(isActive ? (isThinking ? "Thinking" : "Current turn") : "")
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
            // Phone scoreboard: avatar + name + turn pill · score with multiplier · shape counts.
            VStack(alignment: .leading, spacing: dense ? 6 : 8) {
                HStack(spacing: 8) {
                    PlayerAvatar(player: player, size: dense ? 22 : 26)
                    Text(player.name.isEmpty ? "Player \(player.id)" : player.name)
                        .font(.system(size: dense ? 13 : 14, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    if isActive { turnPill }
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(player.score)")
                        .font(Theme.display(dense ? 26 : 30, relativeTo: .title))
                        .monospacedDigit()
                        .foregroundStyle(Theme.foreground)
                        .contentTransition(.numericText(value: Double(player.score)))
                        .animation(.easeOut(duration: 0.25), value: player.score)
                    MultiplierPill(multiplier: player.multiplier)
                    ScoreDelta(score: player.score, multiplier: player.multiplier)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 6) {
                    ShapeCounts(player: player, size: 11)
                    Spacer(minLength: 0)
                    if isMine { SeatTag(text: "You", color: Theme.link) }
                    if isHost { SeatTag(text: "Host") }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .opacity(isActive ? 1 : 0.88)

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

    /// "Your turn" / "Turn" / "Thinking" in the player's own colour, on the active phone card.
    private var turnPill: some View {
        HStack(spacing: 5) {
            if isThinking {
                ProgressView().controlSize(.mini).tint(onColor)
            } else {
                Image(systemName: "circle.fill").font(.system(size: 6)).symbolEffect(.pulse)
            }
            Text(isThinking ? "Thinking" : (isMine ? "Your turn" : "Turn"))
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(onColor)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(color, in: Capsule())
        .fixedSize()
        .layoutPriority(1)
    }

    private var onColor: Color { Color.isLight(hex: player.colorHex) ? Color.black.opacity(0.78) : .white }

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

/// The phone scoreboard: two cards side by side, or a 2×2 grid for 3–4 players (web `PlayerCards`).
struct PlayerStrip<Session: GamePresenting>: View {
    let session: Session

    var body: some View {
        let players = session.game.players
        let dense = players.count > 2
        let columns = min(players.count, 2)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(players) { player in
                let active = player.id == session.currentPlayer.id && !session.isOver
                PlayerCard(
                    player: player,
                    variant: .compact(dense: dense),
                    isActive: active,
                    isMine: player.id == session.mySeatID,
                    isHost: session.capabilities.isOnline && player.id == 1,
                    isThinking: active && session.isCPUThinking
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
