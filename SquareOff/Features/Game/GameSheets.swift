import Charts
import SquareOffCore
import SwiftUI

/// Bottom-sheet game menu (web `GameMenu`): players with show-shapes switches, preferences,
/// How to play, Reset, Leave.
struct GameMenuSheet<Session: GamePresenting>: View {
    @Bindable var session: Session
    let onReset: () -> Void
    let onLeave: () -> Void
    let onRules: () -> Void

    @AppStorage("soundEnabled") private var soundEnabled = true
    @AppStorage(MusicPlayer.defaultsKey) private var musicEnabled = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("starsEnabled") private var starsEnabled = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3").foregroundStyle(Theme.muted)
                Text("Game menu").font(Theme.display(18, relativeTo: .headline)).foregroundStyle(Theme.foreground)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.subheadline.weight(.bold)).foregroundStyle(Theme.muted).frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close menu")
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 12)
            Theme.separator.frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let code = session.capabilities.roomCode {
                        VStack(alignment: .leading, spacing: 4) {
                            SectionLabel("Room code")
                            Text(String(code)).font(Theme.display(22, relativeTo: .title2)).tracking(2.5).monospacedDigit().foregroundStyle(Theme.foreground)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Players")
                        ForEach(session.game.players) { player in
                            PlayerCard(player: player, variant: .row(seat: nil, showsScore: true), isMine: player.id == session.mySeatID,
                                       isHost: session.capabilities.isOnline && player.id == 1) {
                                Toggle("Show \(player.name)'s shapes", isOn: visibility(for: player.id))
                                    .labelsHidden()
                                    .tint(Theme.accent)
                            }
                        }
                        ForEach(0..<session.spectatorCount, id: \.self) { _ in SpectatorRow() }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel("Preferences")
                        SettingsToggle(title: "Sound effects", isOn: $soundEnabled)
                        SettingsToggle(title: "Music", isOn: $musicEnabled)
                        SettingsToggle(title: "Haptics", isOn: $hapticsEnabled)
                        SettingsToggle(title: "Starfield", isOn: $starsEnabled)
                    }
                    .padding(16)
                    .card()

                    VStack(spacing: 8) {
                        Button { onRules() } label: { Label("How to play", systemImage: "book") }
                            .buttonStyle(TertiaryButtonStyle())
                        if session.capabilities.canReset {
                            Button {
                                dismiss()
                                onReset()
                            } label: { Label("Reset game", systemImage: "arrow.counterclockwise") }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                        Button {
                            dismiss()
                            onLeave()
                        } label: { Label(session.capabilities.isOnline ? "Leave room" : "Leave game", systemImage: "rectangle.portrait.and.arrow.right") }
                        .buttonStyle(DangerButtonStyle())
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
        }
    }

    private func visibility(for owner: Int) -> Binding<Bool> {
        Binding(
            get: { !session.hiddenShapeOwners.contains(owner) },
            set: { visible in
                if visible { session.hiddenShapeOwners.remove(owner) } else { session.hiddenShapeOwners.insert(owner) }
            }
        )
    }
}

/// Results (web `GameOverModal`): standings, per-player stats, score chart and the exits.
/// Dismissable; the "Results" button in the banner reopens it.
struct GameOverSheet<Session: GamePresenting>: View {
    let session: Session
    let onExit: (AppModel.GameExit) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let standings = session.game.standings
        let isOver = session.isOver
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    Image(systemName: "trophy").foregroundStyle(Theme.warning)
                    Text(isOver ? "GAME OVER" : "SCORES SO FAR")
                        .font(Theme.display(20, relativeTo: .title3)).tracking(1.5).foregroundStyle(Theme.foreground)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.subheadline.weight(.bold)).foregroundStyle(Theme.muted).frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close results")
                }
                .padding(.top, 16)

                if isOver {
                    summary(standings)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(isOver ? "Final standings" : "Standings")
                    ForEach(Array(ranks(standings).enumerated()), id: \.element.player.id) { _, entry in
                        PlayerCard(player: entry.player, variant: .result(rank: isOver ? entry.rank : entry.position),
                                   isMine: entry.player.id == session.mySeatID,
                                   isHost: session.capabilities.isOnline && entry.player.id == 1)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { ForEach(standings) { statCard($0) } }
                    VStack(spacing: 10) { ForEach(standings) { statCard($0) } }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Score over time").font(Theme.display(15, relativeTo: .subheadline)).foregroundStyle(Theme.foreground)
                        Spacer()
                        HStack(spacing: 10) {
                            ForEach(session.game.players) { player in
                                HStack(spacing: 4) {
                                    Circle().fill(Color(hex: player.colorHex)).frame(width: 8, height: 8)
                                    Text(player.name).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                                }
                            }
                        }
                    }
                    ScoreChart(players: session.game.players, showsTitle: false).frame(height: 220)
                }
                .padding(14)
                .card()

                footer
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private func summary(_ standings: [PlayerState]) -> some View {
        Group {
            if session.game.isDraw {
                (Text("Tie game").fontWeight(.bold) + Text(" · same score, shapes and diamonds"))
            } else {
                (Text(standings[0].name).fontWeight(.bold) + Text(" wins · \(standings[0].score) pts"))
            }
        }
        .font(.subheadline)
        .foregroundStyle(Theme.foregroundSecondary)
    }

    /// Ranks with ties shared at the top (the web shows 1, 1, 3 for a tied pair).
    private func ranks(_ standings: [PlayerState]) -> [(position: Int, rank: Int, player: PlayerState)] {
        standings.enumerated().map { index, player in
            let rank = index == 1 && session.game.isDraw ? 1 : index + 1
            return (index + 1, rank, player)
        }
    }

    private func statCard(_ player: PlayerState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PlayerIdentity(player: player, nameFont: .system(size: 13, weight: .semibold))
            HStack(spacing: 14) {
                Stat(label: "Score", value: "\(player.score)", size: 20)
                Stat(label: "Squares", value: "\(player.squares.count)", size: 20)
                Stat(label: "Diamonds", value: "\(player.diamonds.count)", size: 20)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    @ViewBuilder
    private var footer: some View {
        let isOnline = session.capabilities.isOnline
        let isHost = session.role == .host
        let isGuest = isOnline && !isHost
        VStack(spacing: 10) {
            if session.isOver {
                if isGuest, session.rematchState != .hostCanStart {
                    Chip(text: "Waiting for the host to restart…", symbol: "hourglass")
                        .frame(maxWidth: .infinity)
                }
                switch session.rematchState {
                case .hostCanStart:
                    Button { session.startRematch() } label: { Label("Start rematch", systemImage: "play.fill") }
                        .buttonStyle(PrimaryButtonStyle())
                case .waitingForHost:
                    EmptyView()
                case .none:
                    if session.capabilities.canRestart {
                        Button { session.restart() } label: {
                            Label(isOnline ? "Rematch" : "Play again", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
                HStack(spacing: 10) {
                    ShareLink(item: shareText) { Label("Share", systemImage: "square.and.arrow.up") }
                        .buttonStyle(TertiaryButtonStyle(fullWidth: false))
                    Spacer()
                    Button("Home") { onExit(.home) }.buttonStyle(TertiaryButtonStyle(fullWidth: false))
                    Button(isGuest ? "Leave" : "New game") { onExit(.setup) }
                        .buttonStyle(SecondaryButtonStyle(fullWidth: false))
                }
            } else {
                Button("Back to game") { dismiss() }.buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private var shareText: String {
        let lines = session.game.standings.map { "\($0.name) \($0.score)" }.joined(separator: " · ")
        return "\(lines) — Square Off"
    }
}

/// Score after each move, one line per player (Swift Charts replaces the web's recharts).
struct ScoreChart: View {
    let players: [PlayerState]
    var showsTitle = true

    private struct Point: Identifiable {
        let id: String
        let player: String
        let move: Int
        let score: Int
    }

    var body: some View {
        let points = players.flatMap { player in
            ([0] + player.scoreHistory).enumerated().map { move, score in
                Point(id: "\(player.id)-\(move)", player: player.name, move: move, score: score)
            }
        }
        let top = max(10, Int((Double(points.map(\.score).max() ?? 0) * 1.1).rounded(.up)))
        VStack(alignment: .leading, spacing: 8) {
            if showsTitle { Text("Score by move").font(.footnote.weight(.semibold)) }
            Chart(points) { point in
                LineMark(x: .value("Move", point.move), y: .value("Score", point.score))
                    .foregroundStyle(by: .value("Player", point.player))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
            }
            .chartForegroundStyleScale(domain: players.map(\.name), range: players.map { Color(hex: $0.colorHex) })
            .chartYScale(domain: 0...top)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Theme.separator)
                    AxisValueLabel().foregroundStyle(Theme.muted).font(.system(size: 11))
                }
            }
            .chartLegend(.hidden)
        }
    }
}

extension Game {
    /// Moves played so far, also after a rebuild from a server snapshot (where `moves` is empty).
    var scoreHistoryLength: Int { max(moves.count, players.first?.scoreHistory.count ?? 0) }
}
