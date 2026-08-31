import Foundation

/// Outcome of refreshing one provider. Failures are values, not thrown errors,
/// so that one broken adapter never cancels the others.
nonisolated enum ProviderResult: Sendable {
    case success(ProviderUsage)
    case failure(provider: ProviderID, error: ProviderError)

    var provider: ProviderID {
        switch self {
        case .success(let usage): usage.provider
        case .failure(let provider, _): provider
        }
    }

    var usage: ProviderUsage? {
        guard case .success(let usage) = self else { return nil }
        return usage
    }
}
