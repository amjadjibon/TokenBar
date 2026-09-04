import Foundation

/// The subset of Grok Build's ACP extension protocol used by TokenBar.
nonisolated enum GrokProtocol {
    static let initializeMethod = "initialize"
    static let authenticateMethod = "authenticate"
    static let billingMethod = "x.ai/billing"

    nonisolated struct InitializeParams: Encodable, Sendable {
        let protocolVersion = 1
        let clientCapabilities = ClientCapabilities()

        nonisolated struct ClientCapabilities: Encodable, Sendable {
            let fs = FileSystemCapabilities()
            let terminal = false

            nonisolated struct FileSystemCapabilities: Encodable, Sendable {
                let readTextFile = false
                let writeTextFile = false
            }
        }
    }

    nonisolated struct InitializeResult: Decodable, Sendable {
        let authMethods: [AuthMethod]?
        let metadata: Metadata?

        nonisolated struct AuthMethod: Decodable, Sendable {
            let id: String
        }

        nonisolated struct Metadata: Decodable, Sendable {
            let defaultAuthMethodID: String?

            private enum CodingKeys: String, CodingKey {
                case defaultAuthMethodID = "defaultAuthMethodId"
            }
        }

        private enum CodingKeys: String, CodingKey {
            case authMethods
            case metadata = "_meta"
        }

        var authenticationMethod: String? {
            if let preferred = metadata?.defaultAuthMethodID,
               authMethods?.contains(where: { $0.id == preferred }) == true
            {
                return preferred
            }
            if authMethods?.contains(where: { $0.id == "cached_token" }) == true {
                return "cached_token"
            }
            return nil
        }
    }

    nonisolated struct AuthenticateParams: Encodable, Sendable {
        let methodId: String
        let metadata = Metadata()

        nonisolated struct Metadata: Encodable, Sendable {
            let headless = true
        }

        private enum CodingKeys: String, CodingKey {
            case methodId
            case metadata = "_meta"
        }
    }

    nonisolated struct EmptyResult: Decodable, Sendable {}
    nonisolated struct EmptyParams: Encodable, Sendable {}

    /// Current response shape from Grok Build's `x.ai/billing` handler. The
    /// deprecated credit fields remain because older CLI backends still return
    /// them instead of `creditUsagePercent` and `currentPeriod`.
    nonisolated struct BillingResult: Decodable, Sendable {
        let config: Config?
        let subscriptionTier: String?

        nonisolated struct Config: Decodable, Sendable {
            let creditUsagePercent: Double?
            let currentPeriod: Period?
            let monthlyLimit: Cent?
            let used: Cent?
            let billingPeriodStart: String?
            let billingPeriodEnd: String?
        }

        nonisolated struct Period: Decodable, Sendable {
            let type: String?
            let start: String?
            let end: String?
        }

        nonisolated struct Cent: Decodable, Sendable {
            let val: Double

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                val = try container.decodeIfPresent(Double.self, forKey: .val) ?? 0
            }

            private enum CodingKeys: String, CodingKey { case val }
        }
    }
}

nonisolated extension GrokProtocol.BillingResult {
    func providerUsage(now: Date = Date()) throws -> ProviderUsage {
        guard let config else { throw ProviderError.invalidResponse }

        let usedPercent: Double?
        if let reported = config.creditUsagePercent {
            usedPercent = reported
        } else if let used = config.used?.val,
                  let limit = config.monthlyLimit?.val,
                  limit > 0
        {
            usedPercent = used / limit * 100
        } else {
            usedPercent = nil
        }
        guard let usedPercent else { throw ProviderError.unavailable }

        let start = Self.date(config.currentPeriod?.start ?? config.billingPeriodStart)
        let reset = Self.date(config.currentPeriod?.end ?? config.billingPeriodEnd)
        let name = Self.windowName(type: config.currentPeriod?.type, start: start, end: reset)

        return ProviderUsage(
            provider: .grok,
            plan: subscriptionTier?.trimmingCharacters(in: .whitespacesAndNewlines),
            limits: [
                UsageLimit(
                    id: name.lowercased(),
                    name: name,
                    usedPercent: usedPercent,
                    resetAt: reset
                )
            ],
            updatedAt: now
        )
    }

    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func windowName(type: String?, start: Date?, end: Date?) -> String {
        let normalized = type?.uppercased() ?? ""
        if normalized.contains("WEEKLY") { return "Weekly" }
        if normalized.contains("MONTHLY") { return "Monthly" }

        if let start, let end {
            let days = end.timeIntervalSince(start) / 86_400
            if (4...12).contains(days) { return "Weekly" }
            if (20...45).contains(days) { return "Monthly" }
        }
        return "Credits"
    }
}
