import Observation
import SwiftUI

/// Bottom-anchored transient messages (HeroUI `Toast.Provider placement="bottom"`).
@Observable
final class ToastCenter {
    struct Toast: Identifiable, Equatable {
        enum Style { case `default`, success, danger, warning }

        let id = UUID()
        let title: String
        var description: String?
        var style: Style = .default
        var actionTitle: String?
        @ObservationIgnored var action: (() -> Void)?

        static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
    }

    private(set) var toasts: [Toast] = []

    func show(_ title: String, description: String? = nil, style: Toast.Style = .default,
              actionTitle: String? = nil, action: (() -> Void)? = nil) {
        // Deduped by title so a repeated socket error doesn't stack.
        guard !toasts.contains(where: { $0.title == title }) else { return }
        let toast = Toast(title: title, description: description, style: style, actionTitle: actionTitle, action: action)
        toasts.append(toast)
        Task {
            try? await Task.sleep(for: .seconds(action == nil ? 4 : 6))
            dismiss(toast.id)
        }
    }

    func success(_ title: String, description: String? = nil) { show(title, description: description, style: .success) }
    func danger(_ title: String, description: String? = nil, retry: (() -> Void)? = nil) {
        show(title, description: description, style: .danger, actionTitle: retry == nil ? nil : "Retry", action: retry)
    }

    func dismiss(_ id: UUID) {
        withAnimation(.easeOut(duration: 0.2)) { toasts.removeAll { $0.id == id } }
    }
}

struct ToastOverlay: View {
    let center: ToastCenter

    var body: some View {
        VStack(spacing: 8) {
            ForEach(center.toasts) { toast in
                ToastView(toast: toast) { center.dismiss(toast.id) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: center.toasts)
        .allowsHitTesting(!center.toasts.isEmpty)
    }
}

private struct ToastView: View {
    let toast: ToastCenter.Toast
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(tint).font(.system(size: 16, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.foreground)
                if let description = toast.description {
                    Text(description).font(.caption).foregroundStyle(Theme.foregroundSecondary)
                }
            }
            Spacer(minLength: 0)
            if let actionTitle = toast.actionTitle {
                Button(actionTitle) {
                    dismiss()
                    toast.action?()
                }
                .buttonStyle(SecondaryButtonStyle(small: true, fullWidth: false))
            }
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(Theme.muted).frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.overlay, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(tint.opacity(0.4)))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
        .onTapGesture(perform: dismiss)
    }

    private var tint: Color {
        switch toast.style {
        case .default: Theme.link
        case .success: Theme.success
        case .danger: Theme.dangerText
        case .warning: Theme.warning
        }
    }

    private var symbol: String {
        switch toast.style {
        case .default: "info.circle"
        case .success: "checkmark.circle"
        case .danger: "exclamationmark.octagon"
        case .warning: "exclamationmark.triangle"
        }
    }
}
