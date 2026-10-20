import SwiftUI

/// The app's backdrop: a faint vertical gradient with slowly drifting stars, a lighter take on
/// the web's `StarsAnimation`. Off via the "Stars" setting or when Reduce Motion is on (static).
struct StarfieldBackground: View {
    @AppStorage("starsEnabled") private var starsEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#151B26"), Theme.background, Color(hex: "#0D0D13")],
                startPoint: .top,
                endPoint: .bottom
            )
            if starsEnabled {
                StarfieldView(animated: !reduceMotion)
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
        let size: Double
        let alpha: Double
        let speed: Double
        let twinkle: Double
        let phase: Double
    }

    /// Fixed layout so the field looks the same on every screen and launch.
    private static let stars: [Star] = {
        var rng = SeededRandom(seed: 0x5157_4152_4546_4F46)
        return (0..<140).map { _ in
            let depth = rng.next()
            return Star(
                x: rng.next(),
                y: rng.next(),
                size: 0.8 + depth * 1.4,
                alpha: 0.12 + depth * 0.22,
                speed: 0.004 + depth * 0.010,
                twinkle: 0.4 + rng.next() * 1.2,
                phase: rng.next() * .pi * 2
            )
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !animated)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas(rendersAsynchronously: true) { ctx, size in
                for star in Self.stars {
                    var y = star.y - (animated ? (t * star.speed).truncatingRemainder(dividingBy: 1) : 0)
                    if y < 0 { y += 1 }
                    let glow = animated ? 0.8 + 0.2 * sin(t * star.twinkle + star.phase) : 1
                    let rect = CGRect(x: star.x * size.width, y: y * size.height, width: star.size, height: star.size)
                    ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(star.alpha * glow)))
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
    /// Full-screen app backdrop (gradient + stars). Replaces a flat `Theme.background`.
    func appBackground() -> some View {
        background(StarfieldBackground())
    }
}
