import SquareOffCore
import SquareOffNet
import SwiftUI

/// Replays a finished game from `GET /{id}/replay`, re-simulating every turn with the rules
/// engine (the server only stores coordinates), with the same tile spins and shape panes as play.
struct ReplayView: View {
    let gameID: Int
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var payload: GameReplayPayload?
    @State private var loadError: String?
    @State private var game: Game?
    @State private var index = 0
    @State private var isPlaying = false
    @State private var speed = 1.0
    @State private var spins: [Cell: SpinEvent] = [:]
    @State private var lastMove: MoveResult?
    @State private var spinSequence = 0
    @State private var note: String?

    var body: some View {
        Group {
            if let payload, let game {
                content(payload, game)
            } else if let loadError {
                ContentUnavailableView("Replay unavailable", systemImage: "film", description: Text(loadError))
            } else {
                ProgressView("Loading replay…")
            }
        }
        .background(Theme.overlay)
        .navigationTitle("Game replay")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close replay")
            }
        }
        .task { await load() }
        .task(id: isPlaying) { await autoplay() }
    }

    private func content(_ payload: GameReplayPayload, _ game: Game) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Game #\(payload.gameId) · \(payload.gameType) · \(payload.boardSize)×\(payload.boardSize). The highlighted card is the side to move; scores update after each move.")
                    .font(.footnote)
                    .foregroundStyle(Theme.foregroundSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(game.players) { player in
                        PlayerCard(player: player, variant: .row(seat: nil, showsScore: true), isActive: player.id == game.currentPlayer.id && index < payload.turns.count)
                    }
                }
                PlaybackBoardView(game: game, spins: spins, lastMove: lastMove)
                    .frame(maxWidth: 420)
                Text(note ?? " ").font(.footnote).foregroundStyle(Theme.textSecondary).frame(minHeight: 20)
                controls(payload)
                ScoreChart(players: game.players)
                    .frame(height: 160)
                    .padding(14)
                    .card()
                if payload.turns.isEmpty {
                    Text("No moves recorded for this game.").font(.footnote).foregroundStyle(Theme.muted)
                }
            }
            .padding(16)
        }
    }

    private func controls(_ payload: GameReplayPayload) -> some View {
        VStack(spacing: 10) {
            Slider(value: Binding(get: { Double(index) }, set: { seek(to: Int($0.rounded())) }),
                   in: 0...Double(max(payload.turns.count, 1)), step: 1)
            HStack(spacing: 10) {
                Button { seek(to: index - 1) } label: { Image(systemName: "backward.frame.fill") }
                    .disabled(index == 0)
                    .accessibilityLabel("Previous move")
                Button {
                    if !isPlaying, index >= payload.turns.count { seek(to: 0) }
                    isPlaying.toggle()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill").frame(minWidth: 60)
                }
                .accessibilityLabel(isPlaying ? "Pause" : "Play")
                Button { step() } label: { Image(systemName: "forward.frame.fill") }
                    .disabled(index >= payload.turns.count)
                    .accessibilityLabel("Next move")
                Spacer()
                Menu {
                    ForEach([0.5, 1.0, 2.0, 4.0], id: \.self) { value in
                        Button(value == speed ? "✓ \(value, specifier: "%g")×" : "\(value, specifier: "%g")×") { speed = value }
                    }
                } label: {
                    Text("\(speed, specifier: "%g")×").font(.subheadline.weight(.semibold)).frame(minWidth: 44)
                }
                Text("Move \(index) / \(payload.turns.count)").font(.footnote.monospacedDigit()).foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(14)
        .card()
    }

    // MARK: Playback

    private func load() async {
        do {
            let payload = try await app.backend.api.replay(gameID: gameID)
            let slots = payload.participants.map(\.boardSlotId).sorted()
            guard (2...4).contains(slots.count), Set(slots).count == slots.count, slots.allSatisfy({ (1...4).contains($0) }) else {
                loadError = "This game's seats can't be replayed."
                return
            }
            self.payload = payload
            seek(to: 0)
        } catch {
            loadError = (error as? APIError)?.status == 403 ? "Replays are only available for games you played." : "Couldn't load this game."
        }
    }

    private func freshGame(_ payload: GameReplayPayload) -> Game {
        // Turn order is the order of the first appearance of each seat in the turn list; the
        // participants' slot order is the fallback for games with no turns.
        var order: [Int] = []
        for turn in payload.turns where !order.contains(turn.boardSlotId) { order.append(turn.boardSlotId) }
        for participant in payload.participants.sorted(by: { $0.boardSlotId < $1.boardSlotId }) where !order.contains(participant.boardSlotId) {
            order.append(participant.boardSlotId)
        }
        let players = order.compactMap { slot -> PlayerState? in
            guard let participant = payload.participants.first(where: { $0.boardSlotId == slot }) else { return nil }
            return PlayerState(id: slot, name: participant.displayName, colorHex: participant.color,
                               isCPU: participant.participantType == "cpu",
                               cpuLevel: participant.cpuType.flatMap(CPULevel.init(rawValue:)))
        }
        return Game(board: Board(size: payload.boardSize), players: players, currentPlayerIndex: 0, timerSeconds: payload.timer)
    }

    private func seek(to target: Int) {
        guard let payload else { return }
        let clamped = max(0, min(target, payload.turns.count))
        var game = freshGame(payload)
        var last: MoveResult?
        for turn in payload.turns.prefix(clamped) {
            guard game.currentPlayer.id == turn.boardSlotId, let move = try? game.place(at: turn.cell) else { break }
            last = move
        }
        self.game = game
        index = clamped
        lastMove = last
        spins = [:]
        note = clamped == payload.turns.count ? "Final position" : nil
        if clamped >= payload.turns.count { isPlaying = false }
    }

    private func step() {
        guard let payload, var game, index < payload.turns.count else { return }
        let turn = payload.turns[index]
        guard game.currentPlayer.id == turn.boardSlotId, let move = try? game.place(at: turn.cell) else {
            note = "The recorded turns don't line up; stopping here."
            isPlaying = false
            return
        }
        spinSequence += 1
        for (tile, event) in SpinSchedule.events(for: move, sequence: spinSequence, continuousIndex: false) { spins[tile] = event }
        lastMove = move
        self.game = game
        index += 1
        note = move.newShapeCount > 0 ? "+\(move.scoreIncrease) for \(game.players.first { $0.id == move.playerID }?.name ?? "")" : nil
        if index >= payload.turns.count { isPlaying = false; note = "Final position" }
    }

    private func autoplay() async {
        guard isPlaying else { return }
        while isPlaying, !Task.isCancelled, let payload, index < payload.turns.count {
            try? await Task.sleep(for: .milliseconds(max(80, Int(650 / speed))))
            guard isPlaying, !Task.isCancelled else { return }
            step()
        }
    }
}
