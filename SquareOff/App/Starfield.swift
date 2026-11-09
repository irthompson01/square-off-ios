import SwiftUI

/// The app's backdrop: the web's radial vignette (`body::before`) with the `StarsAnimation`
/// canvas over it. Off via the "Starfield" setting; a single static frame under Reduce Motion;
/// paused while the app is in the background.
struct StarfieldBackground: View {
    @AppStorage("starsEnabled") private var starsEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Theme.background
            RadialGradient(
                stops: [
                    .init(color: Color(hex: "#18222E"), location: 0),
                    .init(color: Theme.background, location: 0.55),
                    .init(color: Color(hex: "#08090D"), location: 1),
                ],
                center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 0,
                endRadius: 900
            )
            if starsEnabled {
                StarfieldView(animated: !reduceMotion && scenePhase == .active)
            }
        }
        .ignoresSafeArea()
    }
}

struct StarfieldView: View {
    let animated: Bool

    private struct Star {
        let x: Double
        let y: Double
        let radius: Double
    }

    /// 200 stars, radius 0.1–2, like the web. Fixed layout so the field looks the same on every launch.
    private static let stars: [Star] = {
        var rng = SeededRandom(seed: 0x5157_4152_4546_4F46)
        return (0..<200).map { _ in
            Star(x: rng.next(), y: rng.next(), radius: 0.1 + rng.next() * 1.9)
        }
    }()

    /// Upward drift in points per second.
    private static let drift = 3.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !animated)) { context in
            let t = animated ? context.date.timeIntervalSinceReferenceDate : 0
            Canvas(rendersAsynchronously: true) { ctx, size in
                let offset = (t * Self.drift).truncatingRemainder(dividingBy: size.height)
                for star in Self.stars {
                    var y = star.y * size.height - offset
                    if y < -2 { y += size.height }
                    let rect = CGRect(x: star.x * size.width - star.radius, y: y - star.radius,
                                      width: star.radius * 2, height: star.radius * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.4)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Tiny deterministic generator for the star layout (SplitMix64).
private struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}

extension View {
    /// Full-screen app backdrop (vignette + stars). Replaces a flat `Theme.background`.
    func appBackground() -> some View {
        background(StarfieldBackground())
    }
}
