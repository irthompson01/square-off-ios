import AuthenticationServices
import CryptoKit
import Security
import SquareOffNet
import SwiftUI

/// Password sign-in and registration, Sign in with Apple (native) and Google/GitHub through a
/// web authentication session. On the mock backend every path signs in the demo account.
struct SignInView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.webAuthenticationSession) private var webAuth

    enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign in"
        case register = "Create account"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .signIn
    @State private var identifier = ""
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isBusy = false
    @State private var error: AuthError?
    @State private var appleNonce = ""

    private var canSubmit: Bool {
        switch mode {
        case .signIn: !identifier.isEmpty && !password.isEmpty
        case .register: !username.trimmingCharacters(in: .whitespaces).isEmpty && email.contains("@") && password.count >= 8
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    if mode == .signIn {
                        TextField("Email or username", text: $identifier)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        TextField("Username", text: $username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    SecureField(mode == .signIn ? "Password" : "Password (8+ characters)", text: $password)
                        .textContentType(mode == .signIn ? .password : .newPassword)
                    Button(action: submitPassword) {
                        HStack {
                            Text(mode.rawValue).bold()
                            if isBusy { Spacer(); ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(!canSubmit || isBusy)
                } footer: {
                    if let error, error != .cancelled {
                        Text(error.localizedDescription).foregroundStyle(Theme.destructive)
                    } else if app.backend.configuration.kind == .mock {
                        Text("Mock server: try \(MockSquareOffAPI.demoUsername) / \(MockSquareOffAPI.demoPassword), or create any account.")
                    }
                }

                Section {
                    appleButton
                    socialButton("Continue with Google", background: Theme.surfaceRaised, foreground: .white) {
                        Image(systemName: "g.circle.fill")
                    } action: { signIn(with: .google) }
                    socialButton("Continue with GitHub", background: Theme.surfaceRaised, foreground: .white) {
                        Image("github-mark").resizable().scaledToFit().frame(width: 20, height: 20)
                    } action: { signIn(with: .github) }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .disabled(isBusy)

                Section {
                    Button("Keep playing as a guest") { dismiss() }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.surface)
            .navigationTitle(mode.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onChange(of: mode) { _, _ in error = nil }
        }
    }

    // MARK: Password

    private func submitPassword() {
        run {
            switch mode {
            case .signIn:
                try await app.accounts.signIn(emailOrUsername: identifier.trimmingCharacters(in: .whitespaces), password: password)
            case .register:
                try await app.accounts.register(username: username.trimmingCharacters(in: .whitespaces),
                                                email: email.trimmingCharacters(in: .whitespaces), password: password)
            }
        }
    }

    // MARK: Apple

    @ViewBuilder
    private var appleButton: some View {
        if app.backend.isLive {
            SignInWithAppleButton(.signIn) { request in
                let raw = AppleSignIn.randomNonce()
                appleNonce = raw
                request.requestedScopes = [.fullName, .email]
                request.nonce = AppleSignIn.sha256(raw)
            } onCompletion: { result in
                handleApple(result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            socialButton("Sign in with Apple", background: .white, foreground: .black) {
                Image(systemName: "apple.logo")
            } action: {
                run { try await app.accounts.signInWithApple(.mock) }
            }
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                error = .server(status: 0)
                return
            }
            let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            let name = [credential.fullName?.givenName, credential.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
            let nonce = appleNonce
            run {
                try await app.accounts.signInWithApple(AppleNativeCredential(
                    identityToken: token, authorizationCode: code, fullName: name.isEmpty ? nil : name, rawNonce: nonce))
            }
        case .failure(let failure):
            if (failure as? ASAuthorizationError)?.code == .canceled { return }
            error = .server(status: 0)
        }
    }

    // MARK: Google / GitHub

    private func signIn(with provider: OAuthProvider) {
        run {
            do {
                try await app.accounts.signInWithProvider(provider) { url, scheme in
                    try await webAuth.authenticate(using: url, callbackURLScheme: scheme, preferredBrowserSession: .shared)
                }
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
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(foreground)
                .background(background, in: RoundedRectangle(cornerRadius: 12))
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
