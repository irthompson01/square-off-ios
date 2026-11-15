import Foundation

/// The Haptics preference, read at trigger time so every `.sensoryFeedback` honours the toggle
/// (mirrors `SoundPlayer`, which reads `soundEnabled` the same way).
nonisolated enum Haptics {
    static let defaultsKey = "hapticsEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }
}
