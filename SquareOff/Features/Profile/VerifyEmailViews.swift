import SwiftUI

/// The page behind the sign-up confirmation link (web `/verify-email?token=…`), opened from the
/// universal link or `squareoff://verify-email?token=…`: redeems the token once, then offers
/// "Log in"; a refused token shows why and the resend form.
struct VerifyEmailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    let token: String

    private enum Status: Equatable {
        case verifying
        case verified(alreadyVerified: Bool)
        case failed(AuthError)
    }

    @State private var status: Status = .verifying

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                switch status {
                case .verifying:
                    AuthCardHeader(symbol: "envelope.badge", title: "Verify email", subtitle: "Confirming your email address")
                    HStack(spacing: 10) {
                        ProgressView().tint(Theme.link)
                        Text("Verifying…").font(.subheadline).foregroundStyle(Theme.foregroundSecondary)
                    }
                    .padding(.vertical, 12)
                case .verified(let alreadyVerified):
                    AuthCardHeader(symbol: "checkmark.seal", title: "Verify email", subtitle: "You're all set")
                    AlertBox(.success, title: alreadyVerified ? "Email already verified" : "Email verified",
                             message: "Your account is ready. Log in to start playing.")
                    Button {
                        dismiss()
                        app.pendingSignIn = .signIn
                        app.selectedTab = .profile
                    } label: {
                        Label("Log in", systemImage: "arrow.right.to.line")
                    }
                    .buttonStyle(PrimaryButtonStyle(large: true))
                case .failed(let error):
                    AuthCardHeader(symbol: "envelope.badge", title: "Verify email", subtitle: "That link didn't work")
                    AlertBox(.danger, message: error.localizedDescription)
                    ResendVerificationForm(prefill: "")
                    footer
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
        .task(id: token) {
            do {
                let response = try await app.accounts.verifyEmail(token: token)
                status = .verified(alreadyVerified: response.alreadyVerified)
            } catch {
                status = .failed(AuthError.wrap(error))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Text("Already verified?").foregroundStyle(Theme.muted)
            Button("Log in") {
                dismiss()
                app.pendingSignIn = .signIn
                app.selectedTab = .profile
            }
            .foregroundStyle(Theme.link)
            .underline()
        }
        .font(.subheadline)
    }
}

/// "Resend the link" on its own (web `/verify-email` without a token): for a login refused with
/// `email_unverified` when the identifier wasn't an address.
struct ResendVerificationView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    let prefill: String

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                AuthCardHeader(symbol: "envelope.arrow.triangle.branch", title: "Resend verification link",
                               subtitle: "Enter your account email and we'll send a new link")
                ResendVerificationForm(prefill: prefill)
                HStack(spacing: 4) {
                    Text("Already verified?").foregroundStyle(Theme.muted)
                    Button("Log in") {
                        dismiss()
                        app.pendingSignIn = .signIn
                        app.selectedTab = .profile
                    }
                    .foregroundStyle(Theme.link)
                    .underline()
                }
                .font(.subheadline)
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
}

/// One email field and "Resend the link". The server answers the same way whether or not the
/// address has a pending account, and so does the toast.
struct ResendVerificationForm: View {
    @Environment(AppModel.self) private var app

    init(prefill: String) {
        _email = State(initialValue: prefill)
    }

    @State private var email: String
    @State private var fieldError: String?
    @State private var isBusy = false

    var body: some View {
        VStack(spacing: 16) {
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
                PendingLabel(title: "Resend the link", pendingTitle: "Sending…", symbol: "paperplane", isPending: isBusy)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(isBusy)
        }
    }

    private func submit() {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard trimmed.wholeMatch(of: SignInView.emailPattern) != nil else {
            fieldError = "Enter a valid email address"
            return
        }
        fieldError = nil
        isBusy = true
        Task {
            defer { isBusy = false }
            await ResendVerificationForm.resend(trimmed, app: app)
        }
    }

    /// Shared by the form and the "check your email" card: the two toasts the web shows.
    static func resend(_ email: String, app: AppModel) async {
        do {
            try await app.accounts.resendVerification(email: email)
            app.toasts.success("Link sent", description: "If that address has an unverified account, a new link has been sent.")
        } catch {
            app.toasts.danger("Couldn't send the link", description: "Please try again in a minute.")
        }
    }
}
