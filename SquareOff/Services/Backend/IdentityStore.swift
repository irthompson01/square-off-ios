import Foundation
import SquareOffNet

/// The device's guest session on a given backend: a `guest_sessions` row plus the 30-day bearer
/// token `POST /create_guest` hands out. The id is persisted in UserDefaults (namespaced per
/// backend: a UUID the docker server minted means nothing to the mock), the token in the
/// Keychain. Calling `create_guest` again with the token renews it and returns the same id.
@MainActor
final class IdentityStore {
    /// Renew when the token has less than this left (the server issues 30 days, sliding).
    static let renewalWindow: TimeInterval = 20 * 86_400

    private let backendID: String
    private let api: any SquareOffAPI
    /// The user's token store: while it holds a token the guest session is never touched.
    private let userTokens: any TokenProvider
    private let guestTokens: any TokenStore
    private let defaults: UserDefaults
    private(set) var guest: GuestIdentity?
    /// One `create_guest` in flight at a time; concurrent callers share it.
    private var minting: Task<GuestIdentity, Error>?

    init(backendID: String, api: any SquareOffAPI, userTokens: any TokenProvider, guestTokens: any TokenStore,
         defaults: UserDefaults = .standard) {
        self.backendID = backendID
        self.api = api
        self.userTokens = userTokens
        self.guestTokens = guestTokens
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.guestKey(backendID)) {
            guest = try? JSONDecoder().decode(GuestIdentity.self, from: data)
        }
        // Pass & Play seats 2–4 used to carry device-minted UUIDs; the server mints their
        // guests itself now, so the old list is dropped.
        defaults.removeObject(forKey: "localSeatIDs.\(backendID)")
    }

    var guestToken: String? { guestTokens.accessToken() }
    var guestTokenExpiry: Date? { guestToken.flatMap(JWT.expiry(of:)) }

    /// No token, or one inside the renewal window. Tokens without `exp` (the mock's) never age.
    var needsRenewal: Bool {
        guard let token = guestToken else { return true }
        guard let expiry = JWT.expiry(of: token) else { return false }
        return expiry.timeIntervalSinceNow < Self.renewalWindow
    }

    /// The cached identity when its token is fresh, else `POST /create_guest` (a renewal when a
    /// token exists, a new session otherwise). Name and colour carry over on renewal.
    func ensureGuest(name: String = "Guest", colorHex: String = Theme.playerColors[0]) async throws -> GuestIdentity {
        if let guest, !needsRenewal { return guest }
        return try await mint(name: guest?.name ?? name, colorHex: guest?.colorHex ?? colorHex)
    }

    /// `RESTClient`'s `SessionRecovery`: the server no longer knows the guest token, so mint a
    /// new session and let the request retry. Never while a user is signed in: their token is
    /// not something to replace quietly. Returns whether a retry makes sense.
    func recoverSession() async -> Bool {
        guard userTokens.accessToken() == nil else { return false }
        guestTokens.clear()
        return (try? await mint(name: guest?.name ?? "Guest", colorHex: guest?.colorHex ?? Theme.playerColors[0])) != nil
    }

    func reset() {
        guest = nil
        guestTokens.clear()
        defaults.removeObject(forKey: Self.guestKey(backendID))
    }

    private func mint(name: String, colorHex: String) async throws -> GuestIdentity {
        if let minting { return try await minting.value }
        let api = api
        let guestTokens = guestTokens
        let task = Task<GuestIdentity, Error> {
            let response = try await api.createGuest(CreateGuestRequest(name: name, color: colorHex))
            if let token = response.accessToken, !token.isEmpty { try guestTokens.store(token) }
            return GuestIdentity(playerID: response.playerId, name: name, colorHex: colorHex)
        }
        minting = task
        defer { minting = nil }
        let created = try await task.value
        guest = created
        defaults.set(try? JSONEncoder().encode(created), forKey: Self.guestKey(backendID))
        return created
    }

    private static func guestKey(_ id: String) -> String { "guestIdentity.\(id)" }
}
