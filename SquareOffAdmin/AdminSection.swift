import SwiftUI

/// The console's sections, in the web sidebar's order (`components/admin/nav.ts`).
enum AdminSection: String, CaseIterable, Identifiable, Hashable {
    case overview, live, users, games, cpus, audit, feedback

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .live: "Live"
        case .users: "Users"
        case .games: "Games"
        case .cpus: "CPUs"
        case .audit: "Audit log"
        case .feedback: "Feedback"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "rectangle.3.group"
        case .live: "dot.radiowaves.left.and.right"
        case .users: "person.2"
        case .games: "gamecontroller"
        case .cpus: "cpu"
        case .audit: "scroll"
        case .feedback: "tray"
        }
    }

    /// Monitor (Overview, Live) and Manage (the rest), the two sidebar groups on iPad.
    var isMonitoring: Bool { self == .overview || self == .live }
}

/// Where a tab's navigation stack can go.
enum AdminRoute: Hashable {
    case user(id: String)
    case cpus, audit, feedback, search, account
}
