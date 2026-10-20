import Foundation
import Observation
import SquareOffNet

struct AppleNativeCredential: Sendable {
    let identityToken: String
    let authorizationCode: String?
    let fullName: String?
    /// The raw nonce whose SHA-256 was handed to Apple.
    let rawNonce: String

    static let mock = AppleNativeCredential(identityToken: "mock-identity-token", authorizationCode: nil, fullName: "Demo Player", rawNonce: "mock-nonce")
}

enum AuthError: LocalizedError, Equatable {
    case invalidCredentials
    case alreadyRegistered
    case tooManyAttempts
    case unreachable
    case appleNoEmail
    case cancelled
    case server(status: Int)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: "Wrong email/username or password."
        case .alreadyRegistered: "That username or email is already taken."
        case .tooManyAttempts: "Too many attempts. Try again in a minute."
        case .unreachable: "Can't reach the server. Check Profile › Developer."
        case .appleNoEmail: "Apple didn't share an email for this account. Remove Square Off under Settings › Apple ID › Sign in with Apple and try again."
        case .cancelled: "Sign-in cancelled."
        case .server(let status): "Sign-in failed (HTTP \(status))."
        }
    }

    static func wrap(_ error: Error) -> AuthError {
        if let auth = error as? AuthError { return auth }
        if let api = error as? APIError {
            switch api {
            case .http(let status, let body):
                if status == 401 { return .invalidCredentials }
                if status == 429 { return .tooManyAttempts }
                if status == 409, body.contains("apple_no_email") { return .appleNoEmail }
                if (400...422).contains(status), body.lowercased().contains("already") { return .alreadyRegistered }
                return .server(status: status)
            case .timeout, .invalidResponse: return .unreachable
            }
        }
        if error is URLError { return .unreachable }
        return .server(status: 0)
    }
}

/// The signed-in or guest state for the current backend, restored from the stored token at
/// launch and on every return to the foreground.
@MainActor
@Observable
final class AccountStore {
    private(set) var account: Account = .guest(nil)
    private(set) var isRestoring = false
    private var backend: Backend

    init(backend: Backend) {
        self.backend = backend
        account = .guest(backend.identity.guest)
    }

    func attach(_ backend: Backend) {
        self.backend = backend
        account = .guest(backend.identity.guest)
    }

    /// Token → `/check-auth` → `/profile`. An expired token is dropped without a round-trip;
    /// a network error keeps the token for the next try but leaves the account as guest.
    func restore() async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        guard let token = backend.tokenStore.accessToken() else {
            account = .guest(backend.identity.guest)
            return
        }
        if JWT.isExpired(token) {
            backend.tokenStore.clear()
            account = .guest(backend.identity.guest)
            return
        }
        do {
            guard try await backend.api.checkAuth() else {
                backend.tokenStore.clear()
                account = .guest(backend.identity.guest)
                return
            }
            account = .signedIn(try await backend.api.profile())
        } catch {
            if let api = error as? APIError, api.isUnauthorized { backend.tokenStore.clear() }
            account = .guest(backend.identity.guest)
        }
    }

    func signIn(emailOrUsername: String, password: String) async throws {
        do {
            let login = try await backend.api.login(LoginRequest(emailOrUsername: emailOrUsername, password: password))
            try await adopt(token: login.accessToken)
        } catch {
            throw AuthError.wrap(error)
        }
    }

    func register(username: String, email: String, password: String) async throws {
        do {
            _ = try await backend.api.register(RegisterRequest(username: username, email: email, password: password))
        } catch {
            throw AuthError.wrap(error)
        }
        try await signIn(emailOrUsername: email, password: password)
    }

    func signInWithApple(_ credential: AppleNativeCredential) async throws {
        do {
            let login = try await backend.api.appleNativeLogin(AppleNativeLoginRequest(
                identityToken: credential.identityToken, nonce: credential.rawNonce,
                authorizationCode: credential.authorizationCode, fullName: credential.fullName))
            try await adopt(token: login.accessToken)
        } catch {
            throw AuthError.wrap(error)
        }
    }

    /// `authenticate` opens the provider's page and returns the `squareoff://auth?token=…`
    /// callback. The mock returns that callback URL directly, so no browser is needed.
    func signInWithProvider(_ provider: OAuthProvider, authenticate: (URL, String) async throws -> URL) async throws {
        let login: OAuthLoginResponse
        do {
            login = try await backend.api.oauthLoginURL(provider, client: .ios)
        } catch {
            throw AuthError.wrap(error)
        }
        let callback = login.url.scheme == OAuthCallback.scheme ? login.url : try await authenticate(login.url, OAuthCallback.scheme)
        guard let token = OAuthCallback.token(from: callback) else { throw AuthError.server(status: 0) }
        try await adopt(token: token)
    }

    func updateProfile(firstName: String?, lastName: String?, colorHex: String?) async throws {
        do {
            try await backend.api.updateProfile(ProfileUpdateRequest(firstName: firstName, lastName: lastName, color: colorHex))
            account = .signedIn(try await backend.api.profile())   // PATCH answers a different shape
        } catch {
            throw AuthError.wrap(error)
        }
    }

    func signOut() async {
        try? await backend.api.logout()
        backend.tokenStore.clear()
        account = .guest(backend.identity.guest)
    }

    /// The identity to play online or record games with; creates the guest row on first use.
    func ensureIdentity() async throws -> Identity {
        if let identity = account.identity { return identity }
        let guest = try await backend.identity.ensureGuest(name: "Guest", colorHex: Theme.playerColors[0])
        account = .guest(guest)
        return Identity(playerID: guest.playerID, displayName: guest.name, colorHex: guest.colorHex)
    }

    private func adopt(token: String?) async throws {
        guard let token, !token.isEmpty else { throw AuthError.server(status: 0) }
        try backend.tokenStore.store(token)
        do {
            account = .signedIn(try await backend.api.profile())
        } catch {
            backend.tokenStore.clear()
            throw AuthError.wrap(error)
        }
    }
}

/// `squareoff://auth?token=<jwt>`: the OAuth return for the app. Swapping to a one-time code
/// later only changes `token(from:)`.
nonisolated enum OAuthCallback {
    static let scheme = "squareoff"

    static func token(from url: URL) -> String? {
        guard url.scheme == scheme, url.host() == "auth" else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "token" }?.value
    }
}
