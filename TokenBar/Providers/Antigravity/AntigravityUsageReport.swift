import Foundation

/// The `agy -p "/usage" --output-format json` envelope.
///
/// Unlike Claude Code, Antigravity reports quota as structured data, so this is
/// a plain decode rather than a text parse.
nonisolated struct AntigravityUsageReport: Decodable, Sendable {
    let status: String?
    let command: Command?

    nonisolated struct Command: Decodable, Sendable {
        let name: String?
        let payload: Payload?

        private enum CodingKeys: String, CodingKey {
            case name
            case payload = "data"
        }
    }

    nonisolated struct Payload: Decodable, Sendable {
        let groups: [Group]
    }

    /// A family of models sharing one set of limits, e.g. "Gemini Models".
    nonisolated struct Group: Decodable, Sendable {
        let name: String
        let buckets: [Bucket]
    }

    nonisolated struct Bucket: Decodable, Sendable {
        let id: String
        let name: String?
        let window: String?
        let remainingFraction: Double?
        let resetTime: Date?

        private enum CodingKeys: String, CodingKey {
            case id, name, window
            case remainingFraction = "remaining_fraction"
            case resetTime = "reset_time"
        }
    }

    var succeeded: Bool { status == nil || status == "SUCCESS" }

    /// Model families stay separate buckets. Averaging them would hide whichever
    /// one is actually about to run out.
    func usageLimits() -> [UsageLimit] {
        (command?.payload?.groups ?? []).flatMap { group in
            group.buckets
                .sorted { Self.rank($0.window) < Self.rank($1.window) }
                .map { bucket in
                    let duration = Self.windowDuration(bucket.window ?? Self.windowName(bucket))
                    return UsageLimit(
                        id: bucket.id,
                        name: "\(Self.groupName(group.name)) \(Self.windowName(bucket))",
                        // Reported 0...1, not a percentage. Rounded because
                        // 0.07 * 100 is 7.000000000000001 in binary floating
                        // point, which would surface in the derived used figure.
                        remainingPercent: bucket.remainingFraction.map {
                            ($0 * 10_000).rounded() / 100
                        },
                        windowStartAt: bucket.resetTime.flatMap { reset in
                            duration.map { reset.addingTimeInterval(-$0) }
                        },
                        resetAt: bucket.resetTime
                    )
                }
        }
    }

    private static let windowOrder = ["5h", "daily", "weekly", "monthly"]

    private static func windowDuration(_ window: String?) -> TimeInterval? {
        switch window?.lowercased() {
        case "5h", "5 hour": 5 * 3600
        case "daily": 24 * 3600
        case "weekly": 7 * 24 * 3600
        default: nil
        }
    }

    /// Shortest window first, matching how the other providers are listed.
    private static func rank(_ window: String?) -> Int {
        guard let window else { return windowOrder.count }
        return windowOrder.firstIndex(of: window.lowercased()) ?? windowOrder.count
    }

    /// "Gemini Models" reads as "Gemini" once it is paired with a window name.
    private static func groupName(_ name: String) -> String {
        guard let range = name.range(of: " models", options: [.caseInsensitive, .anchored, .backwards]) else {
            return name
        }
        return String(name[..<range.lowerBound])
    }

    private static func windowName(_ bucket: Bucket) -> String {
        switch bucket.window?.lowercased() {
        case "5h": return "5 hour"
        case "daily": return "Daily"
        case "weekly": return "Weekly"
        case "monthly": return "Monthly"
        default: break
        }
        // Fall back to the bucket's own label: "Weekly Limit Remaining" → "Weekly".
        if let name = bucket.name {
            return name.replacingOccurrences(
                of: " Limit Remaining", with: "", options: .caseInsensitive
            )
        }
        return bucket.window ?? bucket.id
    }
}
