import Foundation
import SquareOffNet

/// Guest ids for this device, namespaced per backend (a UUID the docker server minted means
/// nothing to the mock). Also hands out stable UUIDs for Pass & Play seats 2–4 so `POST /start`
/// creates guest rows for them and every seat gets a participant id (and thus a replay).
@MainActor
final class IdentityStore {
    private let backendID: String
    private let api: any SquareOffAPI
    private let defaults: UserDefaults
    private(set) var guest: GuestIdentity?
    private(set) var localSeatIDs: [String]

    init(backendID: String, api: any SquareOffAPI, defaults: UserDefaults = .standard) {
        self.backendID = backendID
        self.api = api
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.guestKey(backendID)) {
            guest = try? JSONDecoder().decode(GuestIdentity.self, from: data)
        }
        if let ids = defaults.stringArray(forKey: Self.seatsKey(backendID)), ids.count == 3 {
            localSeatIDs = ids
        } else {
            localSeatIDs = (0..<3).map { _ in UUID().uuidString.lowercased() }
            defaults.set(localSeatIDs, forKey: Self.seatsKey(backendID))
        }
    }

    /// `POST /create_guest` once, then the cached identity.
    func ensureGuest(name: String, colorHex: String) async throws -> GuestIdentity {
        if let guest { return guest }
        let response = try await api.createGuest(CreateGuestRequest(name: name, color: colorHex))
        let created = GuestIdentity(playerID: response.playerId, name: name, colorHex: colorHex)
        guest = created
        defaults.set(try? JSONEncoder().encode(created), forKey: Self.guestKey(backendID))
        return created
    }

    func reset() {
        guest = nil
        defaults.removeObject(forKey: Self.guestKey(backendID))
        localSeatIDs = (0..<3).map { _ in UUID().uuidString.lowercased() }
        defaults.set(localSeatIDs, forKey: Self.seatsKey(backendID))
    }

    private static func guestKey(_ id: String) -> String { "guestIdentity.\(id)" }
    private static func seatsKey(_ id: String) -> String { "localSeatIDs.\(id)" }
}
