import Foundation

/// A provider's quota state at a point in time. The common currency all
/// adapters convert their native response into.
nonisolated struct ProviderUsage: Codable, Sendable, Equatable {
    let provider: ProviderID
    let plan: String?
    let limits: [UsageLimit]
    let updatedAt: Date

    init(provider: ProviderID, plan: String? = nil, limits: [UsageLimit], updatedAt: Date = Date()) {
        self.provider = provider
        self.plan = plan
        self.limits = limits
        self.updatedAt = updatedAt
    }

    /// Lowest remaining quota across this provider's windows — the number that
    /// actually constrains the user.
    var lowestRemainingPercent: Double? {
        limits.compactMap(\.remainingPercent).min()
    }

    func freshness(now: Date = Date()) -> Freshness {
        Freshness(age: now.timeIntervalSince(updatedAt))
    }
}

/// How much to trust a snapshot's age.
nonisolated enum Freshness: Sendable, Equatable {
    case fresh
    case stale
    case veryStale

    init(age: TimeInterval) {
        switch age {
        case ..<(10 * 60): self = .fresh
        case ..<(30 * 60): self = .stale
        default: self = .veryStale
        }
    }

    var needsWarning: Bool { self != .fresh }
}
