import Foundation
import OSLog

/// Caches the last successful `ProviderUsage` per provider so the menu shows
/// real numbers immediately at launch and keeps showing them when a refresh fails.
actor SnapshotStore {
    private let logger = Logger(subsystem: TokenBarLog.subsystem, category: "storage")

    func loadAll() -> [ProviderID: ProviderUsage] {
        var result: [ProviderID: ProviderUsage] = [:]
        for provider in ProviderID.allCases {
            if let usage = try? JSONFile.read(ProviderUsage.self, from: AppPaths.cachedUsage(provider)) {
                result[provider] = usage
            }
        }
        return result
    }

    func save(_ usage: ProviderUsage) {
        do {
            try AppPaths.createDirectories()
            try JSONFile.write(usage, to: AppPaths.cachedUsage(usage.provider))
        } catch {
            logger.error(
                "[\(usage.provider.rawValue, privacy: .public)] could not cache snapshot: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
