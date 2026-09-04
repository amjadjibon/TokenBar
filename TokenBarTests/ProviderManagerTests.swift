import Foundation
import Testing
@testable import TokenBar

/// Stands in for a real adapter so the manager's isolation behaviour can be
/// tested without touching a CLI.
private struct StubProvider: UsageProvider {
    let id: ProviderID
    var delay: Duration = .zero
    var failure: ProviderError?

    func fetchUsage() async throws -> ProviderUsage {
        if delay > .zero { try await Task.sleep(for: delay) }
        if let failure { throw failure }
        return ProviderUsage(
            provider: id,
            limits: [UsageLimit(id: "w", name: "Weekly", usedPercent: 25)]
        )
    }
}

struct ProviderManagerTests {
    @Test func refreshesOnlyEnabledProviders() async {
        let manager = ProviderManager(providers: [
            StubProvider(id: .claude),
            StubProvider(id: .codex),
            StubProvider(id: .grok),
            StubProvider(id: .antigravity),
        ])
        let results = await manager.refresh([.claude, .codex])
        #expect(Set(results.map(\.provider)) == [.claude, .codex])
    }

    @Test func oneFailureDoesNotAffectTheOthers() async {
        let manager = ProviderManager(providers: [
            StubProvider(id: .claude, failure: .authenticationRequired),
            StubProvider(id: .codex),
        ])
        let results = await manager.refresh([.claude, .codex])

        let claude = try? #require(results.first { $0.provider == .claude })
        guard case .failure(_, let error)? = claude else {
            Issue.record("Expected Claude to fail")
            return
        }
        #expect(error == .authenticationRequired)
        #expect(results.first { $0.provider == .codex }?.usage != nil)
    }

    /// The reason a provider cannot report has to survive to the menu: a missing
    /// relay is "not set up", not "tool not found".
    @Test func reportsTheProvidersOwnReasonForFailing() async {
        let manager = ProviderManager(providers: [
            StubProvider(id: .claude, failure: .providerNotConfigured),
            StubProvider(id: .codex, failure: .executableNotFound),
        ])
        let results = await manager.refresh([.claude, .codex])

        var reasons: [ProviderID: ProviderError] = [:]
        for result in results {
            if case .failure(let provider, let error) = result { reasons[provider] = error }
        }
        #expect(reasons[.claude] == .providerNotConfigured)
        #expect(reasons[.codex] == .executableNotFound)
    }

    /// A hung adapter must not hold up the rest of the refresh.
    @Test func aSlowProviderTimesOutWithoutBlockingTheRest() async {
        let manager = ProviderManager(
            providers: [
                StubProvider(id: .claude, delay: .seconds(30)),
                StubProvider(id: .codex),
            ],
            timeout: .milliseconds(100)
        )

        let clock = ContinuousClock()
        let start = clock.now
        let results = await manager.refresh([.claude, .codex])
        let elapsed = clock.now - start

        #expect(elapsed < .seconds(5))
        #expect(results.count == 2)
        guard case .failure(_, let error)? = results.first(where: { $0.provider == .claude }) else {
            Issue.record("Expected Claude to time out")
            return
        }
        #expect(error == .timeout)
        #expect(results.first { $0.provider == .codex }?.usage != nil)
    }
}
