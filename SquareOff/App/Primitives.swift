import SwiftUI

// The `ui/*` primitives of the web client, as SwiftUI views.

/// Neutral uppercase eyebrow above a group (web `SectionLabel`).
struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.display(12, relativeTo: .caption))
            .tracking(1.4)
            .foregroundStyle(Theme.muted)
    }
}

/// The single title of a page: Grapple for one or two words, display face otherwise, with an
/// optional description (web `PageHeading`).
struct PageHeading: View {
    let title: String
    var description: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.title(title))
                .foregroundStyle(Theme.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            if let description {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(Theme.foregroundSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Label + display-face number (web `Stat`). A positive `delta` shows as a green "+n".
struct Stat: View {
    enum Tone { case `default`, success, warning, danger }

    let label: String
    let value: String
    var tone: Tone = .default
    var delta: Int = 0
    var size: CGFloat = 24
    var symbol: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.caption).foregroundStyle(Theme.muted) }
                Text(label.uppercased())
                    .font(Theme.display(10.5, relativeTo: .caption2))
                    .tracking(1.2)
                    .foregroundStyle(Theme.muted)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(Theme.display(size, relativeTo: .title2))
                    .monospacedDigit()
                    .foregroundStyle(color)
                if delta > 0 {
                    Text("+\(delta)").font(Theme.display(13, relativeTo: .caption)).foregroundStyle(Theme.success)
                }
            }
        }
    }

    private var color: Color {
        switch tone {
        case .default: Theme.foreground
        case .success: Theme.success
        case .warning: Theme.warning
        case .danger: Theme.dangerText
        }
    }
}

/// Small status pill (HeroUI `Chip`).
struct Chip: View {
    enum Style { case `default`, accent, accentFilled, success, warning, danger }

    let text: String
    var style: Style = .default
    var symbol: String?
    var dot = false

    var body: some View {
        HStack(spacing: 5) {
            if dot { Circle().fill(foreground).frame(width: 6, height: 6) }
            if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
            Text(text)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(foreground)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(background, in: Capsule())
    }

    private var foreground: Color {
        switch style {
        case .default: Theme.foreground
        case .accent: Theme.link
        case .accentFilled: .white
        case .success: Theme.success
        case .warning: Theme.warning
        case .danger: Theme.dangerText
        }
    }

    private var background: Color {
        switch style {
        case .default: Theme.controlFill
        case .accent: Theme.accent.opacity(0.18)
        case .accentFilled: Theme.accent
        case .success: Theme.success.opacity(0.16)
        case .warning: Theme.warning.opacity(0.16)
        case .danger: Theme.danger.opacity(0.18)
        }
    }
}

/// Static callout / inline alert (HeroUI `Alert`).
struct AlertBox<Actions: View>: View {
    enum Status { case `default`, accent, success, warning, danger }

    let status: Status
    let title: String?
    let message: String?
    @ViewBuilder var actions: Actions

    init(_ status: Status, title: String? = nil, message: String? = nil, @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.status = status
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 4) {
                if let title {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(titleColor)
                }
                if let message {
                    Text(message).font(.subheadline).foregroundStyle(Theme.foregroundSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                actions
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(status == .default ? 0.08 : 0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.35)))
    }

    private var tint: Color {
        switch status {
        case .default: Theme.foregroundSecondary
        case .accent: Theme.link
        case .success: Theme.success
        case .warning: Theme.warning
        case .danger: Theme.dangerText
        }
    }

    private var titleColor: Color { status == .default ? Theme.foreground : tint }

    private var symbol: String {
        switch status {
        case .default: "flag.checkered"
        case .accent: "info.circle"
        case .success: "lightbulb"
        case .warning: "exclamationmark.triangle"
        case .danger: "xmark.octagon"
        }
    }
}

/// Dashed placeholder for an empty list (web `EmptyState`).
struct EmptyState<Actions: View>: View {
    let symbol: String
    let title: String
    let text: String
    @ViewBuilder var actions: Actions

    init(symbol: String, title: String, text: String, @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.symbol = symbol
        self.title = title
        self.text = text
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(Theme.muted)
                .frame(width: 48, height: 48)
                .background(Theme.surfaceSecondary, in: Circle())
            Text(title).font(Theme.display(16, relativeTo: .headline)).foregroundStyle(Theme.foreground)
            Text(text).font(.subheadline).foregroundStyle(Theme.foregroundSecondary).multilineTextAlignment(.center)
            HStack(spacing: 8) { actions }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [6, 5])))
    }
}

/// Skeleton row placeholder while something loads.
struct SkeletonBar: View {
    var width: CGFloat? = nil
    var height: CGFloat = 14

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Theme.surfaceTertiary.opacity(0.7))
            .frame(width: width, height: height)
    }
}

/// "Square Off" in Grapple with the web's gradient fill and white glow (`.wordmark`).
struct Wordmark: View {
    enum Size { case hero, nav }

    let size: Size
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let big = sizeClass == .regular
        let glows: [CGFloat] = size == .hero ? (big ? [12, 28, 42] : [5, 10, 15]) : (big ? [8, 18, 28] : [5, 11, 18])
        Text("Square Off")
            .font(Theme.game(size == .hero ? (big ? 96 : 52) : 22))
            .tracking(-1)
            .lineLimit(size == .hero && !big ? 2 : 1)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.6)
            .foregroundStyle(
                LinearGradient(colors: [.white, Color(hex: "#E8E8E8"), .white.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .shadow(color: .white.opacity(0.8), radius: glows[0])
            .shadow(color: .white.opacity(0.6), radius: glows[1])
            .shadow(color: Color(hex: "#E8E8E8").opacity(0.4), radius: glows[2])
            .accessibilityLabel("Square Off")
    }
}

/// Home tile: a player-colour gradient on the button recipe (web `HomeNeonButton`).
struct NeonTile: View {
    enum Tone { case sky, rose, emerald, amber }

    let tone: Tone
    let symbol: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 18, weight: .bold))
                Text(title.uppercased())
                    .font(Theme.display(17, relativeTo: .headline))
                    .tracking(1)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(
                LinearGradient(colors: gradient, startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.3), lineWidth: 1)
            )
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.white.opacity(0.35))
                    .frame(height: 1)
                    .padding(.horizontal, 20)
                    .padding(.top, 1)
            }
            .shadow(color: .black.opacity(0.55), radius: 20, y: 12)
        }
        .buttonStyle(NeonPressStyle())
    }

    private var gradient: [Color] {
        switch tone {
        case .sky: [Color(hex: "#38BDF8"), Color(hex: "#0369A1")]
        case .rose: [Color(hex: "#FB7185"), Color(hex: "#BE123C")]
        case .emerald: [Color(hex: "#34D399"), Color(hex: "#065F46")]
        case .amber: [Color(hex: "#F59E0B"), Color(hex: "#92400E")]
        }
    }

    private struct NeonPressStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .brightness(configuration.isPressed ? 0.08 : 0)
                .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
        }
    }
}

/// Mode / tab segmented control in the web's `ToggleButtonGroup` style: pill track on
/// `controlFill`, selected segment on `segment` with link-blue text.
struct SegmentedPills<Option: Hashable & Identifiable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    var symbol: ((Option) -> String)? = nil
    var compact = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let selected = option == selection
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selection = option }
                } label: {
                    HStack(spacing: 6) {
                        if let symbol, !compact { Image(systemName: symbol(option)).font(.system(size: 13, weight: .bold)) }
                        Text(title(option)).lineLimit(1).minimumScaleFactor(0.75)
                    }
                    .font(Theme.display(compact ? 13 : 14, relativeTo: .subheadline))
                    .foregroundStyle(selected ? Theme.link : Theme.foregroundSecondary)
                    .padding(.horizontal, compact ? 6 : 10)
                    .frame(maxWidth: .infinity, minHeight: compact ? 32 : 40)
                    .background(selected ? Theme.accent.opacity(0.18) : .clear, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(Theme.controlFill, in: Capsule())
    }
}

/// Toggle styled like the web's HeroUI `Switch` (accent when on).
struct SettingsToggle: View {
    let title: String
    var description: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.foreground)
                if let description {
                    Text(description).font(.caption).foregroundStyle(Theme.muted)
                }
            }
        }
        .tint(Theme.accent)
    }
}

/// Tokenised text field: label, field, optional help or error (web `TextField`).
struct LabeledField<Field: View>: View {
    let label: String
    var help: String? = nil
    var error: String? = nil
    @ViewBuilder var field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline.weight(.medium)).foregroundStyle(Theme.foreground)
            field
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(error == nil ? Theme.fieldBorder : Theme.danger))
            if let error {
                Text(error).font(.caption).foregroundStyle(Theme.dangerText)
            } else if let help {
                Text(help).font(.caption).foregroundStyle(Theme.muted)
            }
        }
    }
}

/// "just now", "3 min ago", "2 h ago", "earlier" (web `format-relative-ago.ts` / `ResumeGameCard`).
enum RelativeAgo {
    /// Continue-card variant: minutes, hours, else "earlier".
    static func coarse(_ date: Date, now: Date = .now) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600)) h ago" }
        return "earlier"
    }

    /// Open-rooms variant: seconds under a minute.
    static func fine(_ date: Date, now: Date = .now) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 10 { return "just now" }
        if seconds < 60 { return "\(Int(seconds))s ago" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        return "\(Int(seconds / 3600)) h ago"
    }
}
