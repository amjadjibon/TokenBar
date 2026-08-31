import Foundation

nonisolated enum QuotaFormat {
    /// "Resets in 2h 14m" while it is close, a weekday or date once it is not.
    static func reset(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let interval = date.timeIntervalSince(now)
        guard interval > 0 else { return "Resetting now" }

        if interval < 24 * 3600 {
            return "Resets in \(duration(interval))"
        }
        if interval < 7 * 24 * 3600 {
            return "Resets \(date.formatted(.dateTime.weekday(.wide).hour().minute()))"
        }
        return "Resets \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }

    /// Rounds down throughout so a countdown never appears to go backwards
    /// between refreshes.
    static func duration(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60

        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        if minutes > 0 { return "\(minutes)m" }
        return "under a minute"
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    static func age(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "Never updated" }
        let interval = now.timeIntervalSince(date)
        if interval < 60 { return "Updated just now" }
        return "Updated \(duration(interval)) ago"
    }

    static func clock(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}
