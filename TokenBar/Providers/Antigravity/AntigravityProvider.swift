import Foundation

/// Reads quota from the user's installed Antigravity CLI.
///
/// `agy -p "/usage" --output-format json` reports zero turns and zero tokens, so
/// polling it costs no quota. Antigravity splits its limits by model family, and
/// TokenBar preserves that split.
nonisolated struct AntigravityProvider: UsageProvider {
    let id: ProviderID = .antigravity

    private let locator: ExecutableLocator
    private let runner: ProcessRunner

    init(locator: ExecutableLocator = .shared, runner: ProcessRunner = ProcessRunner()) {
        self.locator = locator
        self.runner = runner
    }

    func fetchUsage() async throws -> ProviderUsage {
        guard let executable = await locator.find("agy") else {
            throw ProviderError.executableNotFound
        }

        let output = try await runner.run(
            executable: executable,
            arguments: ["-p", "/usage", "--output-format", "json"]
        )
        guard output.exitCode == 0 else {
            throw ProviderError.processFailed(output.exitCode)
        }

        return try Self.parse(output.stdout)
    }

    static func parse(_ stdout: String, now: Date = Date()) throws -> ProviderUsage {
        guard let report = JSONFile.decodeCommandOutput(AntigravityUsageReport.self, from: stdout)
        else { throw ProviderError.invalidResponse }

        guard report.succeeded else { throw ProviderError.invalidResponse }

        let limits = report.usageLimits()
        guard !limits.isEmpty else { throw ProviderError.unavailable }

        return ProviderUsage(provider: .antigravity, limits: limits, updatedAt: now)
    }
}
