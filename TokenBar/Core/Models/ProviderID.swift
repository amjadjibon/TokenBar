import Foundation

/// Identifies a supported AI subscription provider.
nonisolated enum ProviderID: String, Codable, CaseIterable, Sendable, Identifiable {
    case claude
    case codex
    case antigravity

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .antigravity: "Antigravity"
        }
    }

    /// Single-letter abbreviation used by the "selected provider" menu bar mode.
    var abbreviation: String {
        switch self {
        case .claude: "C"
        case .codex: "X"
        case .antigravity: "A"
        }
    }
}
