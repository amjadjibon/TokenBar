import Foundation

/// Races `work` against a deadline. Used to keep one slow provider from
/// stalling a whole refresh.
nonisolated func withTimeout<T: Sendable>(
    _ duration: Duration,
    work: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T?.self) { group in
        group.addTask { try await work() }
        group.addTask {
            try await Task.sleep(for: duration)
            return nil
        }

        defer { group.cancelAll() }

        while let result = try await group.next() {
            guard let result else { throw ProviderError.timeout }
            return result
        }
        throw ProviderError.timeout
    }
}
