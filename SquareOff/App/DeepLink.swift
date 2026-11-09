import Foundation

/// Every URL the app opens: the `squareoff://` scheme (OAuth return, invites, reset links) and
/// the universal links Apple routes here from square-off.com (`/guest/<code>`,
/// `/reset-password?token=…`). Parsing never trusts the host for the custom scheme beyond its
/// path, and ignores anything else.
nonisolated enum DeepLink: Equatable {
    /// `squareoff://join/<code>` or `https://<host>/guest/<code>`.
    case join(code: Int)
    /// `squareoff://reset-password?token=…` or `https://square-off.com/reset-password?token=…`.
    case passwordReset(token: String)
    /// `squareoff://verify-email?token=…` or `https://square-off.com/verify-email?token=…` (the
    /// sign-up confirmation email).
    case verifyEmail(token: String)
    /// `squareoff://auth?…`: consumed by the web auth session, nothing for the app to do.
    case authCallback(URL)

    static let scheme = OAuthCallback.scheme

    static func parse(_ url: URL) -> DeepLink? {
        let parts = url.pathComponents.filter { $0 != "/" }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let token = query.first { $0.name == "token" }?.value?.trimmingCharacters(in: .whitespacesAndNewlines)

        if url.scheme == scheme {
            switch url.host() {
            case "auth": return .authCallback(url)
            case "join": return parts.last.flatMap(Int.init).map { .join(code: $0) }
            case "reset-password":
                if let token, !token.isEmpty { return .passwordReset(token: token) }
                return parts.first.map { .passwordReset(token: $0) }
            case "verify-email":
                if let token, !token.isEmpty { return .verifyEmail(token: token) }
                return parts.first.map { .verifyEmail(token: $0) }
            default: return nil
            }
        }
        guard url.scheme == "https" || url.scheme == "http" else { return nil }
        if let index = parts.firstIndex(of: "guest"), parts.indices.contains(index + 1), let code = Int(parts[index + 1]) {
            return .join(code: code)
        }
        if parts.first == "reset-password" {
            if let token, !token.isEmpty { return .passwordReset(token: token) }
            if parts.count > 1 { return .passwordReset(token: parts[1]) }
        }
        if parts.first == "verify-email" {
            if let token, !token.isEmpty { return .verifyEmail(token: token) }
            if parts.count > 1 { return .verifyEmail(token: parts[1]) }
        }
        return nil
    }
}

/// A password-reset token on its way to `ResetPasswordView` (identifiable for `.sheet(item:)`).
nonisolated struct ResetToken: Identifiable, Equatable {
    let token: String
    var id: String { token }
}

/// An email-verification token on its way to `VerifyEmailView`.
nonisolated struct VerifyToken: Identifiable, Equatable {
    let token: String
    var id: String { token }
}

/// Which sign-in sheet to open: log in, create an account, or the "check your email" state a
/// just-registered address is waiting in.
nonisolated enum SignInRoute: Identifiable, Equatable {
    case signIn
    case register
    case checkEmail(String)

    var id: String {
        switch self {
        case .signIn: "signIn"
        case .register: "register"
        case .checkEmail(let email): "checkEmail:\(email)"
        }
    }
}
