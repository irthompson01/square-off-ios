import Observation
import SquareOffNet
import SwiftUI

/// One async read with the web's `useAdminQuery` semantics: `loading` on the first fetch,
/// `refreshing` while data is already on screen, the last data kept through a failed refresh,
/// and a stale answer (an earlier call still in flight) never overwriting a newer one.
@Observable
final class AdminQuery<Value: Sendable> {
    enum Status: Equatable { case idle, loading, refreshing, failed }

    private(set) var value: Value?
    private(set) var status: Status = .idle
    private(set) var error: String?
    private(set) var updatedAt: Date?
    private let fetch: @Sendable () async throws -> Value
    private var sequence = 0
    private var inFlight: Task<Void, Never>?

    init(_ fetch: @escaping @Sendable () async throws -> Value) {
        self.fetch = fetch
    }

    var isBusy: Bool { status == .loading || status == .refreshing }

    /// Starts a fetch; a call while one is running cancels the older one's result.
    func refresh() async {
        sequence += 1
        let mine = sequence
        status = value == nil ? .loading : .refreshing
        do {
            let result = try await fetch()
            guard mine == sequence else { return }
            value = result
            error = nil
            updatedAt = .now
            status = .idle
        } catch {
            guard mine == sequence else { return }
            self.error = AdminErrors.message(for: error)
            status = .failed
            if let api = error as? APIError, api.status == 403 { AdminErrors.forbidden?() }
        }
    }

    /// Keeps the current data but forgets the error (after a successful write, for example).
    func clearError() {
        error = nil
        if status == .failed { status = .idle }
    }
}

/// A paged list with filters: changing the query goes back to page one; paging keeps it.
@Observable
final class PagedQuery<Item: Sendable, Query: Equatable & Sendable> {
    static var pageSize: Int { 50 }

    private(set) var query: Query
    private(set) var page = 0
    private(set) var total = 0
    private(set) var items: [Item] = []
    private(set) var status: AdminQuery<Paged<AdminUserRow>>.Status = .idle
    private(set) var error: String?
    private let fetch: @Sendable (Query, PageRequest) async throws -> (total: Int, items: [Item])
    private var sequence = 0

    init(query: Query, fetch: @escaping @Sendable (Query, PageRequest) async throws -> (total: Int, items: [Item])) {
        self.query = query
        self.fetch = fetch
    }

    var pages: Int { max(1, (total + Self.pageSize - 1) / Self.pageSize) }
    var isBusy: Bool { status == .loading || status == .refreshing }
    var isEmpty: Bool { items.isEmpty && status == .idle }
    var rangeLabel: String {
        guard total > 0 else { return "0 of 0" }
        return "\(page * Self.pageSize + 1)–\(min(total, (page + 1) * Self.pageSize)) of \(total)"
    }

    func setQuery(_ query: Query) async {
        guard query != self.query else { return }
        self.query = query
        page = 0
        await load()
    }

    func goTo(page index: Int) async {
        guard index >= 0, index < pages, index != page else { return }
        page = index
        await load()
    }

    func load() async {
        sequence += 1
        let mine = sequence
        status = items.isEmpty ? .loading : .refreshing
        do {
            let result = try await fetch(query, .page(page, size: Self.pageSize))
            guard mine == sequence else { return }
            total = result.total
            items = result.items
            error = nil
            status = .idle
        } catch {
            guard mine == sequence else { return }
            self.error = AdminErrors.message(for: error)
            status = .failed
            if let api = error as? APIError, api.status == 403 { AdminErrors.forbidden?() }
        }
    }
}

/// Error copy shared by every section, and the hook that drops back to the gate on a 403.
enum AdminErrors {
    /// Set by `AdminRootView`: the role was revoked mid-session.
    nonisolated(unsafe) static var forbidden: (@MainActor () -> Void)?

    static func message(for error: Error) -> String {
        if let api = error as? APIError {
            switch api {
            case .timeout: return "The server didn't answer in time."
            case .invalidResponse: return "Unexpected answer from the server."
            case .http(let status, _):
                if status == 429 { return "Too many admin requests. Try again in a few minutes." }
                if status == 403 { return "This account is no longer an admin." }
                if let detail = api.detail, detail.count <= 160, !detail.contains("<"), !detail.contains("{") { return detail }
                return "The server answered HTTP \(status)."
            }
        }
        if error is URLError { return "Can't reach the server. Check your connection." }
        return error.localizedDescription
    }
}
