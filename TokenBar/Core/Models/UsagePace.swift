import Foundation

/// Whether the observed rate of quota use can last until this window resets.
nonisolated enum UsagePace: Sendable, Equatable {
    case above
    case within

    static func evaluate(
        earlierUsed: Double,
        currentUsed: Double,
        elapsed: TimeInterval,
        timeUntilReset: TimeInterval
    ) -> UsagePace? {
        guard elapsed >= 15 * 60,
              timeUntilReset > 0,
              currentUsed >= earlierUsed
        else { return nil }

        let rate = (currentUsed - earlierUsed) / elapsed
        return currentUsed >= 100 || currentUsed + rate * timeUntilReset > 100 ? .above : .within
    }

    var message: String {
        switch self {
        case .above: "Above pace · may run out before reset"
        case .within: "Within pace · likely to last until reset"
        }
    }
}
