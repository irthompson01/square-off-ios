import Foundation
import SquareOffCore

/// Persists the unfinished local game (web `use-local-game-persistence.ts`, but in UserDefaults so
/// it survives a relaunch). Only the config and the move list are stored; the game is rebuilt by
/// replaying the moves through the rules engine.
nonisolated struct LocalGameStore: @unchecked Sendable {
    struct Snapshot: Codable, Equatable {
        var version = 1
        var config: GameConfig
        var moves: [Cell]
        var savedAt: Date
    }

    static let key = "localGame"
    static let currentVersion = 1

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> Snapshot? {
        guard let data = defaults.data(forKey: Self.key),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.version == Self.currentVersion else { return nil }
        return snapshot
    }

    func save(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.key)
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
