import Foundation

/// Identifies a supported AI subscription provider.
nonisolated enum ProviderID: String, Codable, CaseIterable, Sendable, Identifiable,
    CodingKeyRepresentable
{
    case claude
    case codex
    case grok
    case antigravity

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .grok: "Grok"
        case .antigravity: "Antigravity"
        }
    }

    /// Single-letter abbreviation used by the "selected provider" menu bar mode.
    var abbreviation: String {
        switch self {
        case .claude: "CL"
        case .codex: "CX"
        case .grok: "GK"
        case .antigravity: "AG"
        }
    }
}
