import Foundation
import SquareOffNet

/// The copy around bulk deactivation (web `bulk-deactivate-bar.tsx`), kept pure for tests.
nonisolated enum UsersBulk {
    static func accounts(_ n: Int) -> String { n == 1 ? "1 account" : "\(n) accounts" }

    static func selectedTitle(_ n: Int) -> String { "Deactivate \(accounts(n))?" }

    static func selectedMessage(_ n: Int) -> String {
        "The \(accounts(n)) you selected are signed out everywhere and can't sign in until reactivated one by one. Superadmins and your own account are skipped."
    }

    static let suspectsTitle = "Deactivate all suspected bots?"

    static func suspectsMessage(_ total: Int) -> String {
        "Every active account that currently matches the suspected-bot filter (\(total), up to 500 per batch) is deactivated and signed out everywhere. Accounts that have played a game are never included."
    }

    static func successTitle(_ result: AdminBulkDeactivateResult) -> String { "Deactivated \(accounts(result.deactivated))" }

    /// nil when nothing was skipped.
    static func skippedDescription(_ result: AdminBulkDeactivateResult) -> String? {
        result.skipped > 0 ? "\(accounts(result.skipped)) skipped: already inactive, a superadmin, or you." : nil
    }

    static let failureTitle = "Couldn't deactivate the accounts"
}
