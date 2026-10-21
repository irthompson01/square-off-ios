import SwiftUI

/// Design tokens from the web client's `globals.css` (see `docs/FRONTEND_DESIGN_SYSTEM.md` in the
/// react repo). Dark only. One accent; the four player colours are identity, never UI chrome.
enum Theme {
    // Surfaces
    static let background = Color(hex: "#121219")
    static let surface = Color(hex: "#1A1A22")
    static let surfaceSecondary = Color(hex: "#20202A")
    static let surfaceTertiary = Color(hex: "#262632")
    static let overlay = Color(hex: "#18181F")
    /// Neutral control fill (secondary buttons, chips, number badges).
    static let controlFill = Color(hex: "#2A2A36")
    /// Selected segment in toggle groups / tabs.
    static let segment = Color(hex: "#2E2E3B")
    static let field = Color(hex: "#202028")
    static let fieldBorder = Color.white.opacity(0.14)
    static let border = Color.white.opacity(0.10)
    static let separator = Color.white.opacity(0.07)

    // Text
    static let foreground = Color(hex: "#F4F4F6")
    static let foregroundSecondary = Color(hex: "#B8B8C2")
    /// Labels, captions, placeholders: the dimmest colour allowed for text.
    static let muted = Color(hex: "#94949D")

    // Status
    static let accent = Color(hex: "#0073C4")
    static let link = Color(hex: "#7AB3FF")
    static let danger = Color(hex: "#D02B31")
    static let dangerText = Color(hex: "#F4958E")
    static let success = Color(hex: "#17C964")
    static let warning = Color(hex: "#F7B750")

    // Board
    static let tileEmpty = Color.white
    static let tileBorder = Color(hex: "#ABABAB")

    /// Default seat colours (`--player-1..4`, also the server's `DEFAULT_COLORS`).
    static let playerColors = ["#4C8BF5", "#DD5144", "#1DA462", "#FFCD46"]
    /// The eight preset swatches (`getPlayerColorPresets()`).
    static let swatches = ["#4C8BF5", "#DD5144", "#1DA462", "#FFCD46", "#8B5CF6", "#EC4899", "#EAB308", "#06B6D4"]

    static let cardRadius: CGFloat = 16

    // Compatibility aliases for the v1 names still used in a few places.
    static var textSecondary: Color { foregroundSecondary }
    static var surfaceRaised: Color { surfaceSecondary }
    static var hairline: Color { border }
    static var destructive: Color { dangerText }
    static var go: Color { accent }

    // MARK: Type

    /// Chakra Petch Bold: headings, buttons, labels and every number (`--font-display`).
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("ChakraPetch-Bold", size: size, relativeTo: style)
    }

    /// Grapple: the wordmark and page titles of two words or fewer (`--font-game`).
    static func game(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .custom("GrappleBRK", size: size, relativeTo: style)
    }

    /// Page titles follow the web's `PageHeading`: Grapple for one or two words, display otherwise.
    static func title(_ text: String, size: CGFloat = 30) -> Font {
        text.split(separator: " ").count <= 2 ? game(size) : display(size, relativeTo: .largeTitle)
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

extension Animation {
    /// CSS `easeOutCubic` (`cubic-bezier(0.215, 0.61, 0.355, 1)`): flips, spins, shape draw-on.
    static func easeOutCubic(_ duration: Double) -> Animation {
        .timingCurve(0.215, 0.61, 0.355, 1, duration: duration)
    }

    /// HeroUI's `ease-out-quad`, used by accordion panels.
    static func easeOutQuad(_ duration: Double) -> Animation {
        .timingCurve(0.25, 0.46, 0.45, 0.94, duration: duration)
    }
}

// MARK: - Panels

/// Tokenised card: `surface` with a 1px border (web `Panel`). A tint makes it a status card.
struct CardBackground: ViewModifier {
    var tint: Color?
    var fill: Color = Theme.surface
    var radius: CGFloat = Theme.cardRadius

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tint.map { $0.opacity(0.12) } ?? fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(tint.map { $0.opacity(0.4) } ?? Theme.border, lineWidth: 1)
            )
    }
}

extension View {
    func card(tint: Color? = nil, fill: Color = Theme.surface, radius: CGFloat = Theme.cardRadius) -> some View {
        modifier(CardBackground(tint: tint, fill: fill, radius: radius))
    }
}

// MARK: - Buttons

/// The one filled action per screen (web `primary`). Pill, display face, 44pt (48pt large).
struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.accent
    var large = false
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.display(large ? 17 : 15, relativeTo: .body))
            .tracking(0.3)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: large ? 48 : 44)
            .background(color, in: Capsule())
            .scaleEffect(configuration.isPressed ? (large ? 0.96 : 0.97) : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Neutral outlined action (web `secondary`).
struct SecondaryButtonStyle: ButtonStyle {
    var small = false
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.display(small ? 13 : 15, relativeTo: .body))
            .tracking(0.3)
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, small ? 12 : 16)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: small ? 36 : 44)
            .background(Theme.controlFill, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.border))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Low-emphasis text button (web `tertiary`).
struct TertiaryButtonStyle: ButtonStyle {
    var small = false
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.display(small ? 13 : 15, relativeTo: .body))
            .tracking(0.3)
            .foregroundStyle(Theme.foregroundSecondary)
            .padding(.horizontal, small ? 12 : 16)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: small ? 36 : 44)
            .background(configuration.isPressed ? Theme.controlFill : .clear, in: Capsule())
    }
}

/// Destructive confirm (web `danger`) or, with `soft`, a destructive entry point in a menu.
struct DangerButtonStyle: ButtonStyle {
    var soft = false
    var small = false
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.display(small ? 13 : 15, relativeTo: .body))
            .tracking(0.3)
            .foregroundStyle(soft ? Theme.dangerText : .white)
            .padding(.horizontal, small ? 12 : 16)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: small ? 36 : 44)
            .background(soft ? Theme.danger.opacity(configuration.isPressed ? 0.2 : 0.15) : Theme.danger, in: Capsule())
            .scaleEffect(configuration.isPressed && !soft ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Icon-only chrome button (web `ghost` + `IconButton`): 40pt hit area, label for VoiceOver.
struct GhostIconButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 40
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.foregroundSecondary)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(GhostButtonStyle())
        .accessibilityLabel(label)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.controlFill : .clear, in: Circle())
    }
}

/// A button whose label is swapped for a spinner and alternate text while a request runs
/// (web `isDisabled` + `Spinner` pattern for actions that navigate away).
struct PendingLabel: View {
    let title: String
    let pendingTitle: String
    let symbol: String?
    let isPending: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isPending {
                ProgressView().controlSize(.small).tint(.white)
            } else if let symbol {
                Image(systemName: symbol)
            }
            Text(isPending ? pendingTitle : title)
        }
    }
}
