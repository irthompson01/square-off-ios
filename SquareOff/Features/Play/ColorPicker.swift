import SwiftUI

/// Player colour trigger: a round button holding the swatch (web `PlayerColorPicker`).
struct ColorSwatchPicker: View {
    @Binding var selection: String
    /// Profile and admin may pick any colour; setup offers only the eight presets.
    var allowCustom = false
    @State private var isPresented = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Button { isPresented = true } label: {
            Circle()
                .fill(Color(hex: selection))
                .frame(width: 28, height: 28)
                .frame(width: 40, height: 40)
                .background(Theme.surfaceSecondary, in: Circle())
                .overlay(Circle().strokeBorder(Theme.border))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Player color")
        .accessibilityValue(ColorNames.name(for: selection))
        .sheet(isPresented: $isPresented) {
            ColorSwatchSheet(selection: $selection, allowCustom: allowCustom)
                .presentationDetents([.height(allowCustom ? 392 : 272)])
                .presentationDragIndicator(.visible)
                // Phones honour the detent; iPad would otherwise show a mostly empty form sheet.
                .presentationFitted(sizeClass == .regular)
                .presentationBackground(Theme.overlay)
        }
    }
}

struct ColorSwatchSheet: View {
    @Binding var selection: String
    var allowCustom = false
    @Environment(\.dismiss) private var dismiss
    @State private var custom: Color

    init(selection: Binding<String>, allowCustom: Bool = false) {
        _selection = selection
        self.allowCustom = allowCustom
        _custom = State(initialValue: Color(hex: selection.wrappedValue))
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Pick a color") { dismiss() }
                .padding(.top, 8)
            VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                ForEach(Theme.swatches, id: \.self) { hex in
                    let selected = selection.uppercased() == hex
                    Button {
                        selection = hex
                        custom = Color(hex: hex)
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 44, height: 44)
                            .overlay {
                                if selected {
                                    Image(systemName: "checkmark").font(.headline.weight(.bold)).foregroundStyle(Theme.background)
                                }
                            }
                            .overlay(Circle().strokeBorder(.white.opacity(selected ? 0.9 : 0.15), lineWidth: 2))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(ColorNames.name(for: hex))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .sensoryFeedback(.selection, trigger: selection) { _, _ in Haptics.isEnabled }
            if allowCustom {
                HStack(spacing: 12) {
                    ColorPicker(selection: $custom, supportsOpacity: false) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Custom color").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.foreground)
                            Text("\(ColorNames.name(for: selection)) · \(selection.uppercased())").font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                    .onChange(of: custom) { _, color in
                        let hex = color.hexString
                        if hex != selection.uppercased() { selection = hex }
                    }
                }
                .padding(14)
                .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            }
            .padding(20)
            Spacer(minLength: 0)
        }
    }
}

/// Names for the preset colours and a hue-based fallback (web `color-presets.ts`).
enum ColorNames {
    static let presets: [String: String] = [
        "#4C8BF5": "Blue", "#DD5144": "Red", "#1DA462": "Green", "#FFCD46": "Yellow",
        "#8B5CF6": "Violet", "#EC4899": "Pink", "#EAB308": "Amber", "#06B6D4": "Cyan", "#0583D2": "Blue",
    ]

    static func name(for hex: String) -> String {
        let key = hex.uppercased().hasPrefix("#") ? hex.uppercased() : "#" + hex.uppercased()
        if let preset = presets[key] { return preset }
        guard key.count == 7, let value = UInt64(key.dropFirst(), radix: 16) else { return "Not set" }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        let maxC = max(r, g, b), minC = min(r, g, b)
        let delta = maxC - minC
        let lightness = (maxC + minC) / 2
        let saturation = delta == 0 ? 0 : delta / (1 - abs(2 * lightness - 1))
        if saturation < 0.12 {
            if lightness < 0.2 { return "Black" }
            if lightness > 0.8 { return "White" }
            return "Grey"
        }
        var hue: Double
        if delta == 0 { hue = 0 }
        else if maxC == r { hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
        else if maxC == g { hue = (b - r) / delta + 2 }
        else { hue = (r - g) / delta + 4 }
        hue *= 60
        if hue < 0 { hue += 360 }
        switch hue {
        case ..<15, 345...: return "Red"
        case ..<45: return "Orange"
        case ..<70: return "Yellow"
        case ..<160: return "Green"
        case ..<200: return "Teal"
        case ..<260: return "Blue"
        case ..<300: return "Violet"
        default: return "Pink"
        }
    }
}

private extension View {
    @ViewBuilder
    func presentationFitted(_ fitted: Bool) -> some View {
        if fitted { presentationSizing(.fitted) } else { self }
    }
}
