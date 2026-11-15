import Foundation
import SquareOffNet

/// The device's guest identity on a given backend: a `guest_sessions` row created once with
/// `POST /create_guest` and reused for every game the device records.
nonisolated struct GuestIdentity: Codable, Equatable, Sendable {
    let playerID: String
    var name: String
    var colorHex: String
}

/// What the recorder and the online rooms need to know about the local player.
nonisolated struct Identity: Sendable, Equatable {
    let playerID: String
    let displayName: String
    let colorHex: String
}

/// Who is playing on this device.
enum Account: Equatable {
    /// `nil` until the device has created its guest identity on the current backend.
    case guest(GuestIdentity?)
    case signedIn(ProfileResponse)

    var displayName: String {
        switch self {
        case .guest: "Guest"
        case .signedIn(let profile): profile.username
        }
    }

    var isSignedIn: Bool {
        if case .signedIn = self { return true }
        return false
    }

    var colorHex: String {
        switch self {
        case .guest(let guest): guest?.colorHex ?? Theme.playerColors[0]
        case .signedIn(let profile): profile.color
        }
    }

    /// User UUID when signed in, guest UUID once created, else nil.
    var serverPlayerID: String? {
        switch self {
        case .guest(let guest): guest?.playerID
        case .signedIn(let profile): profile.id
        }
    }

    var identity: Identity? {
        guard let serverPlayerID else { return nil }
        return Identity(playerID: serverPlayerID, displayName: displayName, colorHex: colorHex)
    }

    var profile: ProfileResponse? {
        if case .signedIn(let profile) = self { return profile }
        return nil
    }
}
