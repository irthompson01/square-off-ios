import AVFoundation
import SwiftUI

/// Low-ceremony SFX player. Each play nudges pitch/volume slightly so repeated taps don't sound
/// robotic (part of the "ASMR" feel). Uses the `.ambient` session: mixes with the user's music
/// and respects the silent switch.
@MainActor
final class SoundPlayer {
    enum Effect: String, CaseIterable {
        case place = "button"
        case spin = "spin"
    }

    static let shared = SoundPlayer()

    private var pools: [Effect: [AVAudioPlayer]] = [:]
    private var next: [Effect: Int] = [:]

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        for effect in Effect.allCases {
            guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "mp3") else { continue }
            // A few players per effect so quick taps can overlap.
            pools[effect] = (0..<3).compactMap { _ in
                let player = try? AVAudioPlayer(contentsOf: url)
                player?.enableRate = true
                player?.prepareToPlay()
                return player
            }
        }
    }

    func play(_ effect: Effect) {
        guard UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true,
              let pool = pools[effect], !pool.isEmpty else { return }
        let index = next[effect, default: 0] % pool.count
        next[effect] = index + 1
        let player = pool[index]
        player.currentTime = 0
        player.rate = Float.random(in: 0.96...1.04)
        player.volume = Float.random(in: 0.85...1)
        player.play()
    }
}
