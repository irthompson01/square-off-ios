import SquareOffCore
import SwiftUI

// The Play page's settings controls. The web uses dropdowns for all of them; here the board and
// timer are steppers, the player count is a pill row and the CPU level a numbered row.

/// One value out of an ordered list, stepped with − / + (VoiceOver: adjustable).
struct SettingStepper<Option: Hashable>: View {
    let title: String
    @Binding var selection: Option
    let options: [Option]
    let label: (Option) -> String

    private var index: Int { options.firstIndex(of: selection) ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.foreground)
            HStack(spacing: 6) {
                Text(label(selection))
                    .font(Theme.display(16, relativeTo: .body))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity, alignment: .leading)
                stepButton("minus", enabled: index > 0) { step(-1) }
                stepButton("plus", enabled: index < options.count - 1) { step(1) }
            }
            .padding(.leading, 12)
            .padding(.trailing, 7)
            .frame(height: 46)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.fieldBorder))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(label(selection))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(1)
            case .decrement: step(-1)
            @unknown default: break
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func step(_ delta: Int) {
        let next = index + delta
        guard options.indices.contains(next) else { return }
        withAnimation(.easeOut(duration: 0.15)) { selection = options[next] }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(enabled ? Theme.foreground : Theme.muted.opacity(0.5))
                .frame(width: 32, height: 32)
                .background(Theme.controlFill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
    }
}

/// A titled pill row for a handful of options (the player count).
struct SettingSegments<Option: Hashable>: View {
    let title: String
    @Binding var selection: Option
    let options: [Option]
    let label: (Option) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.foreground)
            SegmentedPills(options: options, selection: $selection, title: label, compact: true)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// The eight CPU levels as a numbered row, the chosen one named underneath. Levels the board
/// size rules out (7–8 below 6×6 or above 12×12) are dimmed.
struct LevelPicker: View {
    @Binding var selection: CPULevel
    let unavailable: Set<CPULevel>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                ForEach(CPULevel.selectable, id: \.self) { level in
                    let selected = level == selection
                    let disabled = unavailable.contains(level)
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { selection = level }
                    } label: {
                        Text("\(level.number)")
                            .font(Theme.display(15, relativeTo: .body))
                            .foregroundStyle(selected ? Theme.link : (disabled ? Theme.muted.opacity(0.45) : Theme.foregroundSecondary))
                            .frame(width: 36, height: 36)
                            .background(selected ? Theme.accent.opacity(0.18) : Theme.controlFill, in: Circle())
                            .overlay(Circle().strokeBorder(selected ? Theme.link : .clear, lineWidth: 1.5))
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScaleStyle())
                    .disabled(disabled)
                    .accessibilityLabel("Level \(level.number), \(level.shortName)")
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
            HStack(spacing: 6) {
                Text("Level \(selection.number)").font(Theme.display(14, relativeTo: .subheadline)).foregroundStyle(Theme.link)
                Text(selection.shortName).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.foreground)
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Small press feedback for round controls.
private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
