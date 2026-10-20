import Charts
import SquareOffCore
import SwiftUI

struct GameMenuSheet: View {
    @Bindable var session: GameSession
    let onLeave: () -> Void

    @AppStorage("soundEnabled") private var soundEnabled = true
    @AppStorage("musicEnabled") private var musicEnabled = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("starsEnabled") private var starsEnabled = true
    @Environment(\.dismiss) private var dismiss
    @State private var confirmLeave = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Show shapes for") {
                    ForEach(session.game.players) { player in
                        Toggle(isOn: visibility(for: player.id)) {
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 4).fill(Color(hex: player.colorHex)).frame(width: 14, height: 14)
                                Text(player.name)
                                Spacer()
                                Text("\(player.score) pts").foregroundStyle(Theme.textSecondary).monospacedDigit()
                            }
                        }
                    }
                }
                Section("Feel") {
                    Toggle("Sound effects", isOn: $soundEnabled)
                    Toggle("Music", isOn: $musicEnabled)
                    Toggle("Haptics", isOn: $hapticsEnabled)
                    Toggle("Stars background", isOn: $starsEnabled)
                }
                Section {
                    NavigationLink("Rules") { RulesView() }
                    Button("Restart") {
                        session.restart()
                        dismiss()
                    }
                    Button("Leave game", role: .destructive) { confirmLeave = true }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Paused")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Leave this game?", isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("Leave game", role: .destructive, action: onLeave)
            } message: {
                Text("Your progress in this game will be lost.")
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

struct GameOverSheet: View {
    let session: GameSession
    let onHome: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let standings = session.game.standings
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    Image(systemName: session.isOver ? "trophy" : "chart.line.uptrend.xyaxis")
                        .font(.system(size: 30))
                        .frame(width: 64, height: 64)
                        .background(Color(hex: standings[0].colorHex).opacity(0.22), in: RoundedRectangle(cornerRadius: 20))
                    Text(headline(standings))
                        .font(Theme.display(28))
                        .multilineTextAlignment(.center)
                    Text("\(session.config.title) · \(session.game.moves.count) moves")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.top, 24)

                VStack(spacing: 8) {
                    ForEach(Array(standings.enumerated()), id: \.element.id) { rank, player in
                        HStack(spacing: 12) {
                            Text("\(rank + 1)").font(.headline).frame(width: 22)
                            RoundedRectangle(cornerRadius: 4).fill(Color(hex: player.colorHex)).frame(width: 14, height: 14)
                            Text(player.name).font(.headline)
                            Spacer()
                            Text("\(player.shapeCount) shapes").font(.footnote).foregroundStyle(Theme.textSecondary)
                            Text("\(player.score)").font(.title3.weight(.heavy)).monospacedDigit().frame(minWidth: 44, alignment: .trailing)
                        }
                        .padding(14)
                        .card(tint: rank == 0 && session.isOver ? Color(hex: player.colorHex) : nil)
                    }
                }

                ScoreChart(players: session.game.players)
                    .frame(height: 180)
                    .padding(14)
                    .card()

                VStack(spacing: 10) {
                    if session.isOver {
                        Button {
                            session.restart()
                        } label: {
                            Label("Rematch", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        HStack(spacing: 10) {
                            Button { onHome() } label: { Label("Home", systemImage: "house") }
                            ShareLink(item: shareText(standings)) { Label("Share", systemImage: "square.and.arrow.up") }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    } else {
                        Button("Back to game") { dismiss() }.buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
            .padding(20)
        }
    }

    private func headline(_ standings: [PlayerState]) -> String {
        guard session.isOver else { return "Scores so far" }
        if session.game.isDraw { return "Tie game" }
        if case .cpu = session.config.mode { return standings[0].isCPU ? "CPU wins" : "You win" }
        return "\(standings[0].name) wins"
    }

    private func shareText(_ standings: [PlayerState]) -> String {
        let lines = standings.map { "\($0.name): \($0.score)" }.joined(separator: ", ")
        return "Square Off \(session.game.board.size)×\(session.game.board.size): \(lines)"
    }
}

/// Score after each move, one line per player (Swift Charts replaces the web's recharts).
struct ScoreChart: View {
    let players: [PlayerState]

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
        VStack(alignment: .leading, spacing: 8) {
            Text("Score by move").font(.footnote.weight(.semibold))
            Chart(points) { point in
                LineMark(x: .value("Move", point.move), y: .value("Score", point.score))
                    .foregroundStyle(by: .value("Player", point.player))
                    .lineStyle(by: .value("Player", point.player))
                    .interpolationMethod(.monotone)
            }
            .chartForegroundStyleScale(domain: players.map(\.name), range: players.map { Color(hex: $0.colorHex) })
            .chartXAxis(.hidden)
            .chartLegend(position: .bottom, alignment: .leading)
        }
    }
}
