import AuthenticationServices
import CryptoKit
import Security
import SquareOffNet
import SwiftUI

/// Log in / Create account (web `AuthCard` + `/login`, `/register`): one centred card with the
/// icon well, title and subtitle, a danger alert for server errors, labelled fields with inline
/// validation, the primary action, an "OR" divider and the three social buttons.
struct SignInView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.webAuthenticationSession) private var webAuth

    enum Mode: String, CaseIterable, Identifiable {
        case signIn, register
        var id: String { rawValue }
    }

    init(initialMode: Mode = .signIn) {
        _mode = State(initialValue: initialMode)
    }

    @State private var mode: Mode
    @State private var identifier = ""
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isBusy = false
    @State private var error: AuthError?
    @State private var fieldErrors: [String: String] = [:]
    @State private var appleNonce = ""
    @State private var showsForgotPassword = false

    static let emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                if let error, error != .cancelled {
                    AlertBox(.danger, message: error.localizedDescription)
                }
                fields
                Button(action: submit) {
                    PendingLabel(title: mode == .signIn ? "Log in" : "Create account",
                                 pendingTitle: mode == .signIn ? "Signing in…" : "Creating account…",
                                 symbol: nil, isPending: isBusy)
                }
                .buttonStyle(PrimaryButtonStyle(large: true))
                .disabled(isBusy)
                divider
                social
                footer
            }
            .padding(24)
            .frame(maxWidth: 448)
            .frame(maxWidth: .infinity)
            .card(fill: Theme.surface)
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.overlay)
        #if !ADMIN_CONSOLE
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.subheadline.weight(.bold)).foregroundStyle(Theme.muted).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .padding(8)
        }
        #endif
        .onChange(of: mode) { _, _ in
            error = nil
            fieldErrors = [:]
        }
        .sheet(isPresented: $showsForgotPassword) {
            ForgotPasswordView(prefill: identifier.contains("@") ? identifier.trimmingCharacters(in: .whitespaces) : "")
                .presentationBackground(Theme.overlay)
        }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: mode == .signIn ? "arrow.right.to.line" : "person.badge.plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.link)
                .frame(width: 48, height: 48)
                .background(Theme.surfaceSecondary, in: Circle())
            Text(mode == .signIn ? "Log in" : "Create account")
                .font(Theme.display(24, relativeTo: .title2))
                .foregroundStyle(Theme.foreground)
                .accessibilityAddTraits(.isHeader)
            Text(mode == .signIn ? "Welcome back" : "It only takes a minute")
                .font(.subheadline)
                .foregroundStyle(Theme.foregroundSecondary)
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private var fields: some View {
        VStack(spacing: 16) {
            if mode == .signIn {
                LabeledField(label: "Email or username", error: fieldErrors["identifier"]) {
                    TextField("you@example.com", text: $identifier)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(Theme.foreground)
                }
            } else {
                LabeledField(label: "Username", error: fieldErrors["username"]) {
                    TextField("your_username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(Theme.foreground)
                }
                LabeledField(label: "Email", help: "Only used for account functions such as login and password reset.", error: fieldErrors["email"]) {
                    TextField("you@example.com", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(Theme.foreground)
                }
            }
            LabeledField(label: "Password", error: fieldErrors["password"]) {
                SecureField("••••••••", text: $password)
                    .textContentType(mode == .signIn ? .password : .newPassword)
                    .foregroundStyle(Theme.foreground)
            }
            if mode == .signIn {
                Button("Forgot password?") { showsForgotPassword = true }
                    .font(.subheadline)
                    .foregroundStyle(Theme.link)
                    .underline()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, -6)
            }
            #if DEBUG
            if app.backend.configuration.kind == .mock {
                Text("Mock server: try \(MockSquareOffAPI.demoUsername) / \(MockSquareOffAPI.demoPassword), or create any account.")
                    .font(.caption).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading)
            }
            #endif
        }
    }

    private var divider: some View {
        HStack(spacing: 12) {
            Theme.separator.frame(height: 1)
            Text("OR").font(Theme.display(11, relativeTo: .caption2)).tracking(2).foregroundStyle(Theme.muted)
            Theme.separator.frame(height: 1)
        }
    }

    private var social: some View {
        VStack(spacing: 10) {
            socialButton("Continue with Google", background: Theme.controlFill, foreground: Theme.foreground) {
                Image(systemName: "g.circle.fill")
            } action: { signIn(with: .google) }
            appleButton
            socialButton("Continue with GitHub", background: Theme.controlFill, foreground: Theme.foreground) {
                Image("github-mark").resizable().scaledToFit().frame(width: 20, height: 20)
            } action: { signIn(with: .github) }
        }
        .disabled(isBusy)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Text(mode == .signIn ? "New here?" : "Already have an account?").foregroundStyle(Theme.muted)
            Button(mode == .signIn ? "Create an account" : "Log in") {
                mode = mode == .signIn ? .register : .signIn
            }
            .foregroundStyle(Theme.link)
            .underline()
        }
        .font(.subheadline)
        .padding(.bottom, 8)
    }

    // MARK: Password

    private func submit() {
        var errors: [String: String] = [:]
        switch mode {
        case .signIn:
            if identifier.trimmingCharacters(in: .whitespaces).isEmpty { errors["identifier"] = "Enter your email or username" }
            if password.isEmpty { errors["password"] = "Enter your password" }
        case .register:
            if username.trimmingCharacters(in: .whitespaces).isEmpty { errors["username"] = "Choose a username" }
            if email.trimmingCharacters(in: .whitespaces).wholeMatch(of: Self.emailPattern) == nil { errors["email"] = "Enter a valid email address" }
            if password.isEmpty { errors["password"] = "Choose a password" }
        }
        fieldErrors = errors
        guard errors.isEmpty else { return }
        run {
            switch mode {
            case .signIn:
                try await app.accounts.signIn(emailOrUsername: identifier.trimmingCharacters(in: .whitespaces), password: password)
                app.toasts.success("Logged in", description: "Welcome back.")
            case .register:
                try await app.accounts.register(username: username.trimmingCharacters(in: .whitespaces),
                                                email: email.trimmingCharacters(in: .whitespaces), password: password)
                app.toasts.success("Account created", description: "You're logged in and ready to play.")
            }
        }
    }

    // MARK: Apple

    @ViewBuilder
    private var appleButton: some View {
        #if ADMIN_CONSOLE
        // The server verifies Apple tokens against the store app's bundle id; admins use a
        // password, Google or GitHub instead.
        EmptyView()
        #else
        if app.backend.isLive {
            SignInWithAppleButton(.continue) { request in
                let raw = AppleSignIn.randomNonce()
                appleNonce = raw
                request.requestedScopes = [.fullName, .email]
                request.nonce = AppleSignIn.sha256(raw)
            } onCompletion: { result in
                handleApple(result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 44)
            .clipShape(Capsule())
        } else {
            #if DEBUG
            socialButton("Continue with Apple", background: .white, foreground: .black) {
                Image(systemName: "apple.logo")
            } action: {
                run {
                    try await app.accounts.signInWithApple(.mock)
                    app.toasts.success("Logged in", description: "Welcome back.")
                }
            }
            #endif
        }
        #endif
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                error = .oauth(OAuthCallback.message(for: "apple_failed"))
                return
            }
            let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            let name = [credential.fullName?.givenName, credential.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
            let nonce = appleNonce
            run {
                try await app.accounts.signInWithApple(AppleNativeCredential(
                    identityToken: token, authorizationCode: code, fullName: name.isEmpty ? nil : name, rawNonce: nonce))
                app.toasts.success("Logged in", description: "Welcome back.")
            }
        case .failure(let failure):
            if (failure as? ASAuthorizationError)?.code == .canceled { return }
            error = .oauth(OAuthCallback.message(for: "apple_failed"))
        }
    }

    // MARK: Google / GitHub

    private func signIn(with provider: OAuthProvider) {
        run {
            do {
                try await app.accounts.signInWithProvider(provider) { url, scheme in
                    try await webAuth.authenticate(using: url, callbackURLScheme: scheme, preferredBrowserSession: .shared)
                }
                app.toasts.success("Logged in", description: "Welcome back.")
            } catch let failure as ASWebAuthenticationSessionError where failure.code == .canceledLogin {
                throw AuthError.cancelled
            }
        }
    }

    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        error = nil
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await operation()
                dismiss()
            } catch {
                self.error = AuthError.wrap(error)
            }
        }
    }

    private func socialButton(_ title: String, background: Color, foreground: Color,
                              @ViewBuilder icon: () -> some View, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label { Text(title) } icon: { icon() }
                .font(Theme.display(15, relativeTo: .body))
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(foreground)
                .background(background, in: Capsule())
                .overlay(Capsule().strokeBorder(background == .white ? .clear : Theme.border))
        }
        .buttonStyle(.plain)
    }
}

enum AppleSignIn {
    static func randomNonce(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
