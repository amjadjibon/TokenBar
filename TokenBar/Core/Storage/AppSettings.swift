import Foundation

nonisolated enum RefreshInterval: Int, Codable, CaseIterable, Sendable, Identifiable {
    case manual = 0
    case oneMinute = 60
    case fiveMinutes = 300
    case tenMinutes = 600
    case fifteenMinutes = 900
    case thirtyMinutes = 1800

    var id: Int { rawValue }

    var duration: Duration? {
        self == .manual ? nil : .seconds(rawValue)
    }

    var displayName: String {
        switch self {
        case .manual: "Manual only"
        case .oneMinute: "1 minute"
        case .fiveMinutes: "5 minutes"
        case .tenMinutes: "10 minutes"
        case .fifteenMinutes: "15 minutes"
        case .thirtyMinutes: "30 minutes"
        }
    }
}

nonisolated enum MenuBarDisplay: String, Codable, CaseIterable, Sendable, Identifiable {
    case lowestRemaining
    case selectedProvider
    case iconOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lowestRemaining: "Lowest remaining quota"
        case .selectedProvider: "Selected provider"
        case .iconOnly: "Icon only"
        }
    }
}

nonisolated struct AppSettings: Codable, Sendable, Equatable {
    var enabledProviders: Set<ProviderID> = Set(ProviderID.allCases)
    var refreshInterval: RefreshInterval = .fiveMinutes
    /// Remaining-quota percentages that trigger a warning notification.
    var warningThresholds: Set<Int> = [20, 10]
    var notifyOnReset: Bool = true
    var menuBarDisplay: MenuBarDisplay = .lowestRemaining
    var selectedProvider: ProviderID = .claude
    var launchAtLogin: Bool = false
    /// Plan names the user typed in, per provider. Not every CLI reports a plan
    /// — Antigravity shows its tier only inside its interactive UI — and the
    /// user knows their own subscription either way.
    var planLabels: [ProviderID: String] = [:]

    static let availableThresholds = [20, 10, 5]

    /// The badge to show beside a provider: what the user typed if they typed
    /// anything, otherwise whatever the provider reported.
    func planLabel(for provider: ProviderID, reported: String?) -> String? {
        let manual = planLabels[provider]?.trimmingCharacters(in: .whitespaces)
        if let manual, !manual.isEmpty { return manual }
        return reported
    }
}
