import Foundation

/// Builds the menu bar's text. Pure, so the choice of which provider the number
/// belongs to can be pinned by tests.
nonisolated enum MenuBarTitle {
    /// Shown when no provider has reported a usable number yet.
    static let unknownPrefix = "TB"

    /// The provider whose quota is tightest right now, and that quota. Ties go
    /// to the earlier provider, so the title does not flicker between two
    /// providers sitting at the same percentage.
    static func tightest(
        among providers: [ProviderID],
        usage: [ProviderID: ProviderUsage]
    ) -> (provider: ProviderID, remainingPercent: Double)? {
        providers
            .compactMap { provider in
                usage[provider]?.lowestRemainingPercent
                    .map { (provider: provider, remainingPercent: $0) }
            }
            .min { $0.remainingPercent < $1.remainingPercent }
    }

    static func text(prefix: String, percent: Double?, warning: Bool) -> String {
        guard let percent else { return "\(prefix) —" }
        let base = "\(prefix) \(Int(percent.rounded()))%"
        return warning ? "\(base) ⚠" : base
    }
}
