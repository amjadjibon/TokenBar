import Foundation

nonisolated struct Notice: Sendable, Equatable {
    let title: String
    let body: String
}

/// Decides which notifications a refresh should produce.
///
/// Kept separate from delivery so the threshold and de-duplication rules can be
/// tested without the notification centre.
nonisolated struct NotificationPlanner: Sendable {
    private struct WarningKey: Hashable {
        let provider: ProviderID
        let limit: String
        let threshold: Int
    }

    /// Warnings already delivered, keyed by provider/limit/threshold. The value
    /// is the quota window they belong to, so a new window re-arms them.
    private var delivered: [WarningKey: Date] = [:]

    init() {}

    /// - Parameter previous: state before this refresh, used to spot a window
    ///   rolling over.
    mutating func plan(
        usage: ProviderUsage,
        previous: ProviderUsage?,
        settings: AppSettings
    ) -> [Notice] {
        var notices: [Notice] = []

        for limit in usage.limits {
            let previousLimit = previous?.limits.first { $0.id == limit.id }
            if let reset = resetNotice(
                limit: limit,
                previous: previousLimit,
                provider: usage.provider,
                settings: settings
            ) {
                notices.append(reset)
            }
            if let warning = warningNotice(limit: limit, provider: usage.provider, settings: settings) {
                notices.append(warning)
            }
        }

        return notices
    }

    private mutating func warningNotice(
        limit: UsageLimit,
        provider: ProviderID,
        settings: AppSettings
    ) -> Notice? {
        guard let remaining = limit.remainingPercent else { return nil }

        // Only the tightest crossed threshold is worth announcing; firing 20%
        // and 10% together for one drop is noise.
        guard let threshold = settings.warningThresholds
            .filter({ remaining < Double($0) })
            .min()
        else { return nil }

        let key = WarningKey(provider: provider, limit: limit.id, threshold: threshold)
        let window = limit.resetAt ?? .distantPast
        guard delivered[key] != window else { return nil }
        delivered[key] = window

        return Notice(
            title: "\(provider.displayName) quota low",
            body: "\(limit.name) is below \(threshold)% remaining."
        )
    }

    private mutating func resetNotice(
        limit: UsageLimit,
        previous: UsageLimit?,
        provider: ProviderID,
        settings: AppSettings
    ) -> Notice? {
        guard let previousReset = previous?.resetAt,
              let currentReset = limit.resetAt,
              currentReset > previousReset
        else { return nil }

        // The window rolled over. Only worth announcing if the user was actually
        // warned about this limit during the window that just ended — otherwise
        // every provider would chime every few hours.
        let keys = delivered.keys.filter { $0.provider == provider && $0.limit == limit.id }
        let wasWarned = keys.contains { delivered[$0] == previousReset }
        for key in keys {
            delivered.removeValue(forKey: key)
        }

        guard settings.notifyOnReset, wasWarned else { return nil }
        return Notice(
            title: "\(provider.displayName) quota reset",
            body: "Your \(limit.name) quota has reset."
        )
    }
}
