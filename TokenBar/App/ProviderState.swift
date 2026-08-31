import Foundation

/// What the menu knows about one provider: the last usage that worked, plus the
/// most recent failure if the latest refresh did not.
nonisolated struct ProviderState: Sendable, Equatable {
    var usage: ProviderUsage?
    var error: ProviderError?

    var hasData: Bool { usage != nil }
}
