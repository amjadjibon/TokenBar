import Foundation

/// Parses the quota lines `claude -p "/usage"` prints.
///
/// Claude Code exposes no structured quota interface, so this reads the report's
/// own text:
///
/// ```
/// Current session: 36% used · resets Sep 1 at 2:29am (Asia/Kuala_Lumpur)
/// Current week (all models): 5% used · resets Sep 6 at 10:59pm (Asia/Kuala_Lumpur)
/// ```
///
/// Only these `Current …:` lines are read; the rest of the report is ignored, so
/// changes elsewhere in it cannot break parsing. A line whose reset stamp cannot
/// be read still yields its percentage.
nonisolated enum ClaudeUsageReport {
    static func parse(_ report: String, now: Date = Date()) -> [UsageLimit] {
        // `Regex` is not Sendable, so it is built per call rather than cached in
        // a static.
        let line = /^Current (?<window>[^:]+):\s*(?<percent>\d+(?:\.\d+)?)%\s+used(?:\s*·\s*resets\s+(?<reset>.+?))?\s*$/

        return report.split(separator: "\n").compactMap { rawLine in
            guard let match = rawLine.trimmingCharacters(in: .whitespaces).wholeMatch(of: line) else {
                return nil
            }
            let window = String(match.window).trimmingCharacters(in: .whitespaces)
            return UsageLimit(
                id: identifier(for: window),
                name: displayName(for: window),
                usedPercent: Double(match.percent),
                resetAt: match.reset.flatMap { resetDate(String($0), now: now) }
            )
        }
    }

    private static func identifier(for window: String) -> String {
        window.lowercased()
            .replacing(/[^a-z0-9]+/, with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func displayName(for window: String) -> String {
        switch window.lowercased() {
        case "session": "Session"
        case "week (all models)": "Weekly"
        default: window.prefix(1).uppercased() + window.dropFirst()
        }
    }

    /// Parses "Sep 1 at 2:29am (Asia/Kuala_Lumpur)".
    ///
    /// Times landing on the hour drop their minutes ("Sep 6 at 11pm"), so both
    /// shapes are tried. The stamp carries no year, so the nearest sensible one
    /// is inferred: a reset that lands well in the past belongs to next year.
    private static func resetDate(_ stamp: String, now: Date) -> Date? {
        let pattern = /^(?<date>.+?)\s*\((?<zone>[^)]+)\)\s*$/
        guard let match = stamp.wholeMatch(of: pattern),
              let zone = TimeZone(identifier: String(match.zone))
        else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let year = calendar.component(.year, from: now)

        let text = String(match.date).trimmingCharacters(in: .whitespaces)
        for candidate in [year, year + 1] {
            formatter.defaultDate = calendar.date(from: DateComponents(year: candidate))
            for format in ["MMM d 'at' h:mma", "MMM d 'at' ha"] {
                formatter.dateFormat = format
                if let parsed = formatter.date(from: text),
                   parsed.timeIntervalSince(now) > -24 * 3600 {
                    return parsed
                }
            }
        }
        return nil
    }
}
