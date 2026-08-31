import Foundation

nonisolated enum ProviderError: Error, Sendable, Equatable {
    case executableNotFound
    case providerNotConfigured
    case authenticationRequired
    case invalidResponse
    case processFailed(Int32)
    case timeout
    case unavailable
}

nonisolated extension ProviderError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .executableNotFound: "Command-line tool not found"
        case .providerNotConfigured: "Not set up yet — see Settings"
        case .authenticationRequired: "Sign-in required"
        case .invalidResponse: "Unexpected response"
        case .processFailed(let code): "Tool exited with code \(code)"
        case .timeout: "Timed out"
        case .unavailable: "Unavailable"
        }
    }
}
