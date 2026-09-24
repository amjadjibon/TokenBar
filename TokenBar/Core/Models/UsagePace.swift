import Foundation

/// Compares quota consumed with the portion of its current window elapsed.
nonisolated enum UsagePace: Sendable, Equatable {
    case above
    case onPace
    case below

    static func evaluate(limit: UsageLimit, now: Date = Date()) -> UsagePace? {
        guard let used = limit.usedPercent,
              let start = limit.windowStartAt,
              let reset = limit.resetAt,
              start < reset,
              (start...reset).contains(now)
        else { return nil }

        let idealUsed = 100 * now.timeIntervalSince(start) / reset.timeIntervalSince(start)
        let difference = used - idealUsed
        if difference > 1 { return .above }
        if difference < -1 { return .below }
        return .onPace
    }

    var message: String {
        switch self {
        case .above: "Above pace"
        case .onPace: "On pace"
        case .below: "Below pace"
        }
    }
}
