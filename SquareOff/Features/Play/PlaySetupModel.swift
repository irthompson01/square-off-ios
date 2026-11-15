import Foundation
import Observation
import SquareOffCore
import SquareOffNet

/// Everything the Play page edits (web `useSetupParams` + `useSetupPlayers`). Lives for the
/// page's lifetime so switching modes keeps every setting, and the board, timer, level, seat
/// count and seat names are remembered on device between visits (`Memory`).
@Observable
final class PlaySetupModel {
    /// What is remembered between visits. The mode, online tab and join code come from the route.
    nonisolated struct Memory: Codable, Equatable {
        var boardSize: Int
        var timer: Int
        var level: CPULevel
        var playerCount: Int
        var players: [SetupPlayer]
        var listPublic: Bool
    }

    static let memoryKey = "playSetup"
    private let defaults: UserDefaults?

    /// `defaults` nil (tests, previews) forgets everything when the page goes away.
    init(remembering defaults: UserDefaults? = nil) {
        self.defaults = defaults
        if let data = defaults?.data(forKey: Self.memoryKey),
           let memory = try? JSONDecoder().decode(Memory.self, from: data) {
            apply(memory)
        }
    }

    var memory: Memory {
        Memory(boardSize: boardSize, timer: timer, level: level, playerCount: playerCount, players: players, listPublic: listPublic)
    }

    /// True when nothing is remembered (tests and previews construct the model this way).
    var defaultsAreOff: Bool { defaults == nil }

    /// Writes the current settings; the page calls it when `memory` changes.
    func persist() {
        guard let defaults, let data = try? JSONEncoder().encode(memory) else { return }
        defaults.set(data, forKey: Self.memoryKey)
    }

    /// Restores a remembered setup, ignoring anything outside today's options.
    private func apply(_ memory: Memory) {
        if Self.boardSizes.contains(memory.boardSize) { boardSize = memory.boardSize }
        if Self.timers.contains(memory.timer) { timer = memory.timer }
        if (2...4).contains(memory.playerCount) { playerCount = memory.playerCount }
        if memory.players.count == players.count, memory.players.map(\.id) == players.map(\.id) { players = memory.players }
        level = CPULevel.selectable.contains(memory.level) && CPUAvailability.isSelectable(memory.level, boardSize: boardSize) ? memory.level : .random
        listPublic = memory.listPublic
    }

    enum Mode: String, CaseIterable, Identifiable {
        case cpu, local, online
        var id: String { rawValue }

        var title: String {
            switch self {
            case .cpu: "vs Computer"
            case .local: "Pass & Play"
            case .online: "Online"
            }
        }

        var symbol: String {
            switch self {
            case .cpu: "cpu"
            case .local: "person.2"
            case .online: "globe"
            }
        }
    }

    enum OnlineTab: String, CaseIterable, Identifiable {
        case create, quick, join, rooms
        var id: String { rawValue }

        var title: String {
            switch self {
            case .create: "Create"
            case .quick: "Quick match"
            case .join: "Join"
            case .rooms: "Rooms"
            }
        }
    }

    static let boardSizes = Array(6...12)
    static let timers = [0, 5, 10, 15, 20, 30, 40, 50, 60]
    static let maxNameLength = 24

    var mode: Mode = .cpu
    var boardSize = 8
    var timer = 0
    var level: CPULevel = .random
    var playerCount = 2
    var players: [SetupPlayer] = (1...4).map { SetupPlayer(id: $0, name: "Player \($0)", colorHex: Theme.playerColors[$0 - 1]) }
    var onlineTab: OnlineTab = .create
    var listPublic = false
    var joinCode = ""
    /// True once the signed-in profile has been copied into seat 1 (done once per account).
    private(set) var prefilledFor: String?

    /// Seats shown in the editor: one for vs Computer and Online, `playerCount` for Pass & Play.
    var visibleSeatCount: Int { mode == .local ? playerCount : 1 }
    var visiblePlayers: [SetupPlayer] { Array(players.prefix(visibleSeatCount)) }

    /// Trimmed, cut to 24 characters, "Player N" when empty (applied only when starting).
    var resolvedPlayers: [SetupPlayer] {
        visiblePlayers.map { seat in
            var seat = seat
            let name = String(seat.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxNameLength))
            seat.name = name.isEmpty ? "Player \(seat.id)" : name
            return seat
        }
    }

    /// "Players 1 and 2 share a color." style hint for the visible seats, nil when all differ.
    var duplicateColorWarning: String? {
        let seats = visiblePlayers
        var groups: [String: [Int]] = [:]
        for seat in seats { groups[seat.colorHex.uppercased(), default: []].append(seat.id) }
        let clashes = groups.values.filter { $0.count > 1 }.sorted { $0[0] < $1[0] }
        guard !clashes.isEmpty else { return nil }
        let lead: String
        if clashes.count == 1 {
            let ids = clashes[0]
            let list = ids.count == 2 ? "\(ids[0]) and \(ids[1])" : ids.dropLast().map(String.init).joined(separator: ", ") + " and \(ids.last!)"
            lead = "Players \(list) share a color."
        } else {
            lead = "Some players share a color."
        }
        return lead + " Pick different colors so tiles are easy to tell apart."
    }

    var isJoinCodeValid: Bool { !joinCode.isEmpty && joinCode.count <= 6 && joinCode.allSatisfy(\.isNumber) }

    func sanitizeJoinCode() {
        joinCode = String(joinCode.filter(\.isNumber).prefix(6))
    }

    func setName(_ name: String, forSeat index: Int) {
        guard players.indices.contains(index) else { return }
        players[index].name = String(name.prefix(Self.maxNameLength))
    }

    /// Seat 1 takes the signed-in profile's name and colour (web prefill), once per account.
    func prefill(from account: Account) {
        guard let profile = account.profile, prefilledFor != profile.id else { return }
        prefilledFor = profile.id
        let full = [profile.firstName, profile.lastName].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        players[0].name = full.isEmpty ? profile.username : full
        if !profile.color.isEmpty { players[0].colorHex = profile.color }
    }

    var primaryTitle: String? {
        switch mode {
        case .cpu: "Start game"
        case .local: "Start local game"
        case .online:
            switch onlineTab {
            case .create: "Create room"
            case .quick: "Find a match"
            case .join: "Join room"
            case .rooms: nil
            }
        }
    }

    var pendingTitle: String {
        mode == .online && onlineTab == .create ? "Creating…" : "Starting…"
    }

    var primarySymbol: String {
        switch mode {
        case .cpu, .local: "play.fill"
        case .online:
            switch onlineTab {
            case .create: "plus"
            case .quick: "bolt.fill"
            case .join: "arrow.right.to.line"
            case .rooms: "play.fill"
            }
        }
    }

    func gameConfig() -> GameConfig {
        GameConfig(
            mode: mode == .cpu ? .cpu(level) : .passAndPlay,
            boardSize: boardSize,
            timerSeconds: timer,
            players: resolvedPlayers
        )
    }

    static func timerLabel(_ seconds: Int) -> String {
        seconds == 0 ? "No timer" : "\(seconds) seconds"
    }

    static func timerPhrase(_ seconds: Int) -> String {
        seconds == 0 ? "no timer" : "a \(seconds)-second timer"
    }
}
