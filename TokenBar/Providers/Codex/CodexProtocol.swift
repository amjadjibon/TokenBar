import Foundation

/// Wire types for the `codex app-server` JSON-RPC protocol. Only the subset
/// TokenBar needs: the handshake and `account/rateLimits/read`.
nonisolated enum CodexProtocol {
    static let initializeMethod = "initialize"
    static let initializedNotification = "initialized"
    static let rateLimitsMethod = "account/rateLimits/read"

    nonisolated struct InitializeParams: Encodable, Sendable {
        let clientInfo: ClientInfo

        nonisolated struct ClientInfo: Encodable, Sendable {
            let name: String
            let title: String
            let version: String
        }
    }

    nonisolated struct EmptyParams: Encodable, Sendable {}

    /// Handshake reply. Contents are unused; decoding it just proves the server
    /// is speaking the expected protocol.
    nonisolated struct InitializeResult: Decodable, Sendable {
        let codexHome: String?
    }

    nonisolated struct RateLimitsResult: Decodable, Sendable {
        let rateLimits: Snapshot
        /// Multi-bucket view keyed by metered limit id (for example `codex`).
        let rateLimitsByLimitId: [String: Snapshot]?
    }

    nonisolated struct Snapshot: Decodable, Sendable {
        let limitId: String?
        let limitName: String?
        let planType: String?
        let primary: Window?
        let secondary: Window?
    }

    nonisolated struct Window: Decodable, Sendable {
        let usedPercent: Double
        /// Epoch seconds.
        let resetsAt: Double?
        let windowDurationMins: Int?

        var resetDate: Date? {
            resetsAt.map { Date(timeIntervalSince1970: $0) }
        }
    }
}

nonisolated extension CodexProtocol.RateLimitsResult {
    /// Flattens every bucket's primary/secondary windows into the shared model.
    func usageLimits() -> [UsageLimit] {
        let buckets: [(key: String, snapshot: CodexProtocol.Snapshot)]
        if let byId = rateLimitsByLimitId, !byId.isEmpty {
            buckets = byId.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        } else {
            buckets = [(rateLimits.limitId ?? "default", rateLimits)]
        }

        // Only worth naming the bucket when there is more than one.
        let prefixed = buckets.count > 1

        return buckets.flatMap { key, snapshot in
            [("primary", snapshot.primary), ("secondary", snapshot.secondary)]
                .compactMap { slot, window -> UsageLimit? in
                    guard let window else { return nil }
                    let windowName = Self.windowName(minutes: window.windowDurationMins, slot: slot)
                    let bucketName = snapshot.limitName ?? key
                    let reset = window.resetDate
                    return UsageLimit(
                        id: "\(key).\(slot)",
                        name: prefixed ? "\(bucketName) \(windowName)" : windowName,
                        usedPercent: window.usedPercent,
                        windowStartAt: reset.flatMap { date in
                            window.windowDurationMins.map { date.addingTimeInterval(-Double($0) * 60) }
                        },
                        resetAt: reset
                    )
                }
        }
    }

    var planType: String? {
        rateLimits.planType ?? rateLimitsByLimitId?.values.compactMap(\.planType).first
    }

    private static func windowName(minutes: Int?, slot: String) -> String {
        guard let minutes else { return slot.capitalized }
        switch minutes {
        case 60: return "Hourly"
        case 300: return "5 hour"
        case 1440: return "Daily"
        case 10080: return "Weekly"
        case 43200: return "Monthly"
        default: break
        }
        if minutes % 1440 == 0 { return "\(minutes / 1440) day" }
        if minutes % 60 == 0 { return "\(minutes / 60) hour" }
        return "\(minutes) min"
    }
}
