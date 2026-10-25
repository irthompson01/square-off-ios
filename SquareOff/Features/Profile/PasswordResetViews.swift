import SwiftUI

/// "Forgot password?" (web `/forgot-password`): one email field, then a success note that
/// never says whether the address has an account.
struct ForgotPasswordView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    init(prefill: String = "") {
        _email = State(initialValue: prefill)
    }

    @State private var email: String
    @State private var fieldError: String?
    @State private var error: AuthError?
    @State private var isBusy = false
    @State private var sent = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                AuthCardHeader(symbol: "envelope", title: "Reset your password",
                               subtitle: "Enter your account email and we'll send a link.")
                if let error {
                    AlertBox(.danger, message: error.localizedDescription)
                }
                if sent {
                    AlertBox(.success, title: "Check your email",
                             message: "If an account exists for that address, we sent a link to reset your password. It works for an hour and only once.")
                    Button("Done") { dismiss() }
                        .buttonStyle(SecondaryButtonStyle())
                } else {
                    LabeledField(label: "Email", error: fieldError) {
                        TextField("you@example.com", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(Theme.foreground)
                            .onSubmit(submit)
                    }
                    Button(action: submit) {
                        PendingLabel(title: "Send reset link", pendingTitle: "Sending…", symbol: "paperplane", isPending: isBusy)
                    }
                    .buttonStyle(PrimaryButtonStyle(large: true))
                    .disabled(isBusy)
                }
            }
            .padding(24)
            .frame(maxWidth: 448)
            .frame(maxWidth: .infinity)
            .card(fill: Theme.surface)
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.overlay)
        .overlay(alignment: .topTrailing) { CloseButton { dismiss() } }
    }

    private func submit() {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard trimmed.wholeMatch(of: SignInView.emailPattern) != nil else {
            fieldError = "Enter a valid email address"
            return
        }
        fieldError = nil
        error = nil
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await app.accounts.requestPasswordReset(email: trimmed)
                sent = true
            } catch {
                self.error = AuthError.wrap(error)
            }
        }
    }
}

/// The page behind the emailed link (web `/reset-password?token=…`), opened from the universal
/// link or `squareoff://reset-password?token=…`.
struct ResetPasswordView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    let token: String

    static let minimumLength = 8

    @State private var password = ""
    @State private var confirm = ""
    @State private var fieldErrors: [String: String] = [:]
    @State private var error: AuthError?
    @State private var isBusy = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                AuthCardHeader(symbol: "key", title: "Reset password", subtitle: "Choose a new password")
                if let error {
                    AlertBox(.danger, message: error.localizedDescription)
                }
                LabeledField(label: "New password", help: "At least \(Self.minimumLength) characters.", error: fieldErrors["password"]) {
                    SecureField("••••••••", text: $password)
                        .textContentType(.newPassword)
                        .foregroundStyle(Theme.foreground)
                }
                LabeledField(label: "Confirm password", error: fieldErrors["confirm"]) {
                    SecureField("••••••••", text: $confirm)
                        .textContentType(.newPassword)
                        .foregroundStyle(Theme.foreground)
                        .onSubmit(submit)
                }
                Button(action: submit) {
                    PendingLabel(title: "Set new password", pendingTitle: "Updating…", symbol: nil, isPending: isBusy)
                }
                .buttonStyle(PrimaryButtonStyle(large: true))
                .disabled(isBusy)
                if error == .resetLinkInvalid {
                    Button("Request a new link") {
                        dismiss()
                        app.pendingForgotPassword = true
                        app.selectedTab = .profile
                    }
                    .buttonStyle(TertiaryButtonStyle())
                }
            }
            .padding(24)
            .frame(maxWidth: 448)
            .frame(maxWidth: .infinity)
            .card(fill: Theme.surface)
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.overlay)
        .overlay(alignment: .topTrailing) { CloseButton { dismiss() } }
    }

    private func submit() {
        var errors: [String: String] = [:]
        if password.count < Self.minimumLength { errors["password"] = "Enter at least \(Self.minimumLength) characters" }
        if confirm != password { errors["confirm"] = "Passwords don't match" }
        fieldErrors = errors
        guard errors.isEmpty else { return }
        error = nil
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await app.accounts.resetPassword(token: token, newPassword: password)
                app.toasts.success("Password updated", description: "Log in with your new password.")
                dismiss()
                app.pendingSignIn = true
                app.selectedTab = .profile
            } catch {
                self.error = AuthError.wrap(error)
            }
        }
    }
}

/// The icon well, title and subtitle the auth cards share (`SignInView` has its own copy with
/// a mode switch).
struct AuthCardHeader: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.link)
                .frame(width: 48, height: 48)
                .background(Theme.surfaceSecondary, in: Circle())
            Text(title)
                .font(Theme.display(24, relativeTo: .title2))
                .foregroundStyle(Theme.foreground)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.foregroundSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
    }
}

struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.subheadline.weight(.bold)).foregroundStyle(Theme.muted).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        .padding(8)
    }
}
