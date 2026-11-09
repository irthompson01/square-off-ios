import AVFoundation
import SwiftUI

/// The looping background track (`harmonies.mp3`, "Music by Missy Cundiff"). One player for the
/// whole session so navigation never restarts it; follows the `musicEnabled` setting (off by default).
@MainActor
final class MusicPlayer {
    static let shared = MusicPlayer()
    static let defaultsKey = "musicEnabled"

    private var player: AVAudioPlayer?

    private init() {}

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.defaultsKey) }

    /// Starts or stops playback to match the saved preference. Safe to call often.
    func sync() {
        if isEnabled { play() } else { pause() }
    }

    private func play() {
        if player == nil {
            guard let url = Bundle.main.url(forResource: "harmonies", withExtension: "mp3") else { return }
            try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            player = try? AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = -1
            player?.volume = 0.6
            player?.prepareToPlay()
        }
        guard let player, !player.isPlaying else { return }
        player.play()
    }

    private func pause() {
        player?.pause()
    }
}

/// Keeps `MusicPlayer` in step with the Music toggle and the scene phase.
struct MusicSync: ViewModifier {
    @AppStorage(MusicPlayer.defaultsKey) private var musicEnabled = false
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onAppear { MusicPlayer.shared.sync() }
            .onChange(of: musicEnabled) { _, _ in MusicPlayer.shared.sync() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { MusicPlayer.shared.sync() }
            }
    }
}

extension View {
    func syncsMusic() -> some View { modifier(MusicSync()) }
}
