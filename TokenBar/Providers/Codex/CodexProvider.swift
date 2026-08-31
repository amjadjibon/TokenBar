import Foundation

/// Reads quota from the user's installed Codex CLI via its local app-server.
///
/// Uses whatever authentication Codex already has; TokenBar never opens
/// `auth.json` or talks to OpenAI directly.
nonisolated struct CodexProvider: UsageProvider {
    let id: ProviderID = .codex

    private let locator: ExecutableLocator

    init(locator: ExecutableLocator = .shared) {
        self.locator = locator
    }

    func fetchUsage() async throws -> ProviderUsage {
        guard let executable = await locator.find("codex") else {
            throw ProviderError.executableNotFound
        }

        let server = CodexAppServer(executable: executable)
        try await server.start()
        defer { Task { await server.stop() } }

        let clientInfo = CodexProtocol.InitializeParams.ClientInfo(
            name: "tokenbar",
            title: "TokenBar",
            version: AppInfo.version
        )
        _ = try await server.request(
            CodexProtocol.initializeMethod,
            params: CodexProtocol.InitializeParams(clientInfo: clientInfo),
            as: CodexProtocol.InitializeResult.self
        )
        try await server.notify(CodexProtocol.initializedNotification)

        let result = try await server.request(
            CodexProtocol.rateLimitsMethod,
            params: CodexProtocol.EmptyParams(),
            as: CodexProtocol.RateLimitsResult.self
        )

        let limits = result.usageLimits()
        guard !limits.isEmpty else { throw ProviderError.unavailable }

        return ProviderUsage(
            provider: .codex,
            plan: result.planType?.capitalized,
            limits: limits
        )
    }
}
