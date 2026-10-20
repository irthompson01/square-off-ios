import SwiftUI

/// Design tokens from the web app (hero-client) and the wireframes. Dark-only for v1.
enum Theme {
    static let background = Color(hex: "#121219")
    static let surface = Color(hex: "#1A1A25")
    static let surfaceRaised = Color(hex: "#232331")
    static let tileEmpty = Color(hex: "#262634")
    static let hairline = Color.white.opacity(0.08)
    static let textSecondary = Color(hex: "#A6A6B8")
    static let link = Color(hex: "#5AB4F0")
    static let go = Color(hex: "#1E9E57")
    static let warning = Color(hex: "#F5A35C")
    static let destructive = Color(hex: "#FF8F8F")

    /// Default seat colours (`DEFAULT_COLORS` on the server, `env.ts` on the web).
    static let playerColors = ["#0583D2", "#FF3131", "#50C878", "#EE8329"]
    /// Extra swatches offered in the colour picker (`color-picker.tsx`).
    static let swatches = ["#0583D2", "#FF3131", "#50C878", "#EE8329", "#8B5CF6", "#06B6D4", "#EAB308", "#EC4899"]

    static let cardRadius: CGFloat = 18

    /// Stand-in for the web's Grapple display font until it's licensed for the app.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black).width(.expanded)
    }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// `#RRGGBB` in sRGB, the format the web and the server store player colours in.
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        let clamp = { (v: CGFloat) in Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }
}

struct CardBackground: ViewModifier {
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(tint.map { $0.opacity(0.16) } ?? Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(tint.map { $0.opacity(0.5) } ?? Theme.hairline, lineWidth: 1)
            )
    }
}

extension View {
    func card(tint: Color? = nil) -> some View {
        modifier(CardBackground(tint: tint))
    }
}

/// Big filled call-to-action used for Play / Start Game / Rematch.
struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Color(hex: "#0583D2")

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(color, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Theme.hairline))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.textSecondary)
    }
}
