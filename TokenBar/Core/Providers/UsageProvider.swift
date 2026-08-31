import Foundation

/// A quota source. Adapters translate one provider's native response into the
/// shared `ProviderUsage` model and know nothing about the UI.
nonisolated protocol UsageProvider: Sendable {
    var id: ProviderID { get }

    /// Produces the current usage, or throws the specific reason it cannot —
    /// tool missing, relay not set up, sign-in needed. That thrown reason is
    /// what the menu shows, so it is worth being precise about.
    func fetchUsage() async throws -> ProviderUsage
}
