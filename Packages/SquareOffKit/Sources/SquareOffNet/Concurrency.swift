import Foundation

/// Runs `operation` and throws `APIError.timeout` if it hasn't finished within `duration`.
/// The slower branch is cancelled either way.
public nonisolated func withTimeout<T: Sendable>(_ duration: Duration, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw APIError.timeout
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
