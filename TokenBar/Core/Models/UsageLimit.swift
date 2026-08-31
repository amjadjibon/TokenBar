import Foundation

/// One quota window reported by a provider.
///
/// Providers report either how much of the window is used or how much is left;
/// whichever is missing is derived here so the UI only deals with one shape.
nonisolated struct UsageLimit: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let name: String
    let usedPercent: Double?
    let remainingPercent: Double?
    let resetAt: Date?
    let metadata: [String: String]?

    init(
        id: String,
        name: String,
        usedPercent: Double? = nil,
        remainingPercent: Double? = nil,
        resetAt: Date? = nil,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.name = name

        let used = usedPercent.map(Self.clamp) ?? remainingPercent.map { 100 - Self.clamp($0) }
        let remaining = remainingPercent.map(Self.clamp) ?? usedPercent.map { 100 - Self.clamp($0) }

        self.usedPercent = used
        self.remainingPercent = remaining
        self.resetAt = resetAt
        self.metadata = metadata
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 100)
    }

    /// Remaining quota as a 0...1 fraction, for progress bars.
    var remainingFraction: Double? {
        remainingPercent.map { $0 / 100 }
    }

    var usedFraction: Double? {
        usedPercent.map { $0 / 100 }
    }

    func timeUntilReset(now: Date = Date()) -> TimeInterval? {
        resetAt.map { $0.timeIntervalSince(now) }
    }
}
