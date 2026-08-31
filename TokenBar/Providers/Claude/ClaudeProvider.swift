import Foundation

/// Reads quota by asking the user's installed Claude Code CLI for its usage
/// report.
///
/// `claude -p "/usage" --output-format json` renders locally: it reports zero
/// turns, zero tokens and zero cost, so polling it does not consume the quota it
/// is reporting on. It uses whatever authentication Claude Code already has —
/// TokenBar never reads credentials or talks to Anthropic directly.
nonisolated struct ClaudeProvider: UsageProvider {
    let id: ProviderID = .claude

    private let locator: ExecutableLocator
    private let runner: ProcessRunner

    init(locator: ExecutableLocator = .shared, runner: ProcessRunner = ProcessRunner()) {
        self.locator = locator
        self.runner = runner
    }

    /// `claude auth status --json`. Only the plan is read; the rest of that
    /// payload identifies the account and is deliberately left alone.
    private struct AuthStatus: Decodable {
        let subscriptionType: String?
    }

    /// The report body, which is the only part of the envelope TokenBar reads.
    private struct Envelope: Decodable {
        let result: String?
        let isError: Bool?

        private enum CodingKeys: String, CodingKey {
            case result
            case isError = "is_error"
        }
    }

    func fetchUsage() async throws -> ProviderUsage {
        guard let executable = await locator.find("claude") else {
            throw ProviderError.executableNotFound
        }

        let output = try await runner.run(
            executable: executable,
            arguments: ["-p", "/usage", "--output-format", "json"]
        )
        guard output.exitCode == 0 else {
            throw ProviderError.processFailed(output.exitCode)
        }

        let usage = try Self.parse(output.stdout)

        // Asked for only once the quota itself parsed, so an account with no
        // subscription never pays for the extra call. Best-effort: a missing
        // badge is not worth failing a refresh over.
        guard let plan = await planName(executable: executable) else { return usage }
        return ProviderUsage(
            provider: usage.provider,
            plan: plan,
            limits: usage.limits,
            updatedAt: usage.updatedAt
        )
    }

    private func planName(executable: URL) async -> String? {
        guard let output = try? await runner.run(
            executable: executable,
            arguments: ["auth", "status", "--json"],
            timeout: .seconds(10)
        ),
            output.exitCode == 0,
            let status = JSONFile.decodeCommandOutput(AuthStatus.self, from: output.stdout)
        else { return nil }

        return PlanName.display(status.subscriptionType)
    }

    static func parse(_ stdout: String, plan: String? = nil, now: Date = Date()) throws -> ProviderUsage {
        guard let envelope = JSONFile.decodeCommandOutput(Envelope.self, from: stdout)
        else { throw ProviderError.invalidResponse }

        guard envelope.isError != true, let report = envelope.result else {
            throw ProviderError.invalidResponse
        }

        let limits = ClaudeUsageReport.parse(report, now: now)
        guard !limits.isEmpty else {
            // A report with no quota lines is what an API-key account looks like:
            // Claude Code works, but there is no subscription quota to show.
            throw ProviderError.unavailable
        }

        return ProviderUsage(provider: .claude, plan: plan, limits: limits, updatedAt: now)
    }
}
