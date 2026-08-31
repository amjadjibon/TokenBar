import Foundation
import OSLog

/// Refreshes every enabled provider concurrently, isolating failures so one
/// broken adapter cannot block or fail the others.
actor ProviderManager {
    private let providers: [ProviderID: any UsageProvider]
    private let timeout: Duration
    private let logger = Logger(subsystem: TokenBarLog.subsystem, category: "providers")

    init(providers: [any UsageProvider], timeout: Duration = .seconds(10)) {
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
        self.timeout = timeout
    }

    func refresh(_ enabled: Set<ProviderID>) async -> [ProviderResult] {
        let selected = providers.values.filter { enabled.contains($0.id) }

        return await withTaskGroup(of: ProviderResult.self) { group in
            for provider in selected {
                group.addTask { [timeout, logger] in
                    do {
                        // No availability pre-check: each adapter's fetch reports
                        // why it cannot produce data far more precisely than a
                        // shared guess could ("needs setup" vs "tool not found").
                        let usage = try await withTimeout(timeout) {
                            try await provider.fetchUsage()
                        }
                        logger.info("[\(provider.id.rawValue, privacy: .public)] refresh completed")
                        return .success(usage)
                    } catch {
                        let providerError = error as? ProviderError ?? .invalidResponse
                        logger.error(
                            "[\(provider.id.rawValue, privacy: .public)] refresh failed: \(String(describing: providerError), privacy: .public)"
                        )
                        return .failure(provider: provider.id, error: providerError)
                    }
                }
            }

            var results: [ProviderResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }
}
