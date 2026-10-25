import Observation
import SquareOffNet
import SwiftUI

/// Console-wide state: the selected section, deep links from launch arguments or search, the
/// feedback badge, and the refresh toggles that survive navigation.
@Observable
final class AdminAppModel {
    var section: AdminSection = .overview
    /// A user to push onto the Users tab (from search, audit rows, feedback senders).
    var pendingUser: String?
    /// A replay to open on the Games tab (`-adminReplay`, search "#123").
    var pendingReplay: Int?
    var newFeedbackCount = 0
    var liveAutoRefresh = true

    init() {
        applyLaunchArguments()
    }

    func open(user id: String) {
        section = .users
        pendingUser = id
    }

    func open(replay gameID: Int) {
        section = .games
        pendingReplay = gameID
    }

    /// Picks up the Debug launch arguments (`-adminSection`, `-adminUser`, `-adminReplay`).
    func applyLaunchArguments(_ defaults: UserDefaults = .standard) {
        #if DEBUG
        if let raw = defaults.string(forKey: "adminSection"), let section = AdminSection(rawValue: raw) {
            self.section = section
        }
        if let user = defaults.string(forKey: "adminUser") { open(user: user) }
        if let replay = defaults.string(forKey: "adminReplay").flatMap(Int.init) { open(replay: replay) }
        #endif
    }
}
