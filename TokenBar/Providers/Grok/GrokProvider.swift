import Foundation

/// Reads the shared Grok subscription usage pool using the user's installed
/// Grok Build CLI and its existing login.
///
/// Newer CLIs own the entire request through the `x.ai/billing` ACP extension.
/// Current stable builds may not expose that method over stdio yet, so the
/// fallback reads only the CLI's bearer token and user id and sends them to the
/// same xAI billing endpoint the CLI uses. Credentials are never returned,
/// logged, cached or added to `ProviderUsage`.
nonisolated struct GrokProvider: UsageProvider {
    let id: ProviderID = .grok

    private let locator: ExecutableLocator
    private let session: URLSession
    private let authFile: URL

    init(
        locator: ExecutableLocator = .shared,
        session: URLSession = .shared,
        authFile: URL = GrokProvider.defaultAuthFile
    ) {
        self.locator = locator
        self.session = session
        self.authFile = authFile
    }

    func fetchUsage() async throws -> ProviderUsage {
        guard let executable = await locator.find("grok") else {
            throw ProviderError.executableNotFound
        }

        if let usage = try? await fetchThroughCLI(executable: executable) {
            return usage
        }
        return try await fetchThroughBillingEndpoint()
    }

    private func fetchThroughCLI(executable: URL) async throws -> ProviderUsage {
        let server = GrokAgentServer(executable: executable)
        try await server.start()

        do {
            let initialized = try await server.request(
                GrokProtocol.initializeMethod,
                params: GrokProtocol.InitializeParams(),
                as: GrokProtocol.InitializeResult.self
            )
            guard let method = initialized.authenticationMethod else {
                throw ProviderError.authenticationRequired
            }
            _ = try await server.request(
                GrokProtocol.authenticateMethod,
                params: GrokProtocol.AuthenticateParams(methodId: method),
                as: GrokProtocol.EmptyResult.self
            )
            let billing = try await server.request(
                GrokProtocol.billingMethod,
                params: GrokProtocol.EmptyParams(),
                as: GrokProtocol.BillingResult.self
            )
            let usage = try billing.providerUsage()
            await server.stop()
            return usage
        } catch {
            await server.stop()
            throw error
        }
    }

    private func fetchThroughBillingEndpoint() async throws -> ProviderUsage {
        let credential = try Self.credential(from: authFile)
        guard let url = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits") else {
            throw ProviderError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 7
        request.setValue("Bearer \(credential.key)", forHTTPHeaderField: "Authorization")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "X-XAI-Token-Auth")
        request.setValue(credential.userID, forHTTPHeaderField: "x-userid")
        request.setValue("cli", forHTTPHeaderField: "x-grok-client-mode")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ProviderError.unavailable
        }

        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ProviderError.authenticationRequired
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ProviderError.unavailable
        }
        guard let billing = try? JSONDecoder().decode(GrokProtocol.BillingResult.self, from: data) else {
            throw ProviderError.invalidResponse
        }
        return try billing.providerUsage()
    }

    private nonisolated struct Credential: Decodable, Sendable {
        let key: String
        let userID: String

        private enum CodingKeys: String, CodingKey {
            case key
            case userID = "user_id"
        }
    }

    static func credential(from data: Data) throws -> (key: String, userID: String) {
        guard let entries = try? JSONDecoder().decode([String: Credential].self, from: data) else {
            throw ProviderError.authenticationRequired
        }
        let ordered = entries.sorted { lhs, rhs in
            let lhsOIDC = lhs.key.hasPrefix("https://auth.x.ai::")
            let rhsOIDC = rhs.key.hasPrefix("https://auth.x.ai::")
            return lhsOIDC && !rhsOIDC
        }
        guard let credential = ordered.map(\.value).first(where: {
            !$0.key.isEmpty && !$0.userID.isEmpty
        }) else {
            throw ProviderError.authenticationRequired
        }
        return (credential.key, credential.userID)
    }

    private static func credential(from url: URL) throws -> (key: String, userID: String) {
        guard let data = try? Data(contentsOf: url) else {
            throw ProviderError.authenticationRequired
        }
        return try credential(from: data)
    }

    private static var defaultAuthFile: URL {
        if let home = ProcessInfo.processInfo.environment["GROK_HOME"], !home.isEmpty {
            return URL(filePath: home).appending(path: "auth.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".grok", directoryHint: .isDirectory)
            .appending(path: "auth.json")
    }
}
