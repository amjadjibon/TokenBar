import Foundation
import Testing
@testable import TokenBar

struct ClaudeProviderTests {
    /// The report carries no year, so parsing is pinned to a known "now".
    private let now = Date(timeIntervalSince1970: 1_788_192_000) // 2026-08-31

    private func fixture(_ name: String) throws -> String {
        try String(decoding: Fixture.data(name), as: UTF8.self)
    }

    @Test func parsesBothQuotaWindows() throws {
        let usage = try ClaudeProvider.parse(fixture("claude-usage.json"), now: now)

        #expect(usage.provider == .claude)
        #expect(usage.limits.count == 2)

        let session = try #require(usage.limits.first)
        #expect(session.id == "session")
        #expect(session.name == "Session")
        #expect(session.usedPercent == 36)
        #expect(session.remainingPercent == 64)
        #expect(session.windowStartAt == session.resetAt?.addingTimeInterval(-5 * 3600))

        let weekly = usage.limits[1]
        #expect(weekly.id == "week-all-models")
        #expect(weekly.name == "Weekly")
        #expect(weekly.usedPercent == 5)
        #expect(weekly.remainingPercent == 95)
        #expect(weekly.windowStartAt == weekly.resetAt?.addingTimeInterval(-7 * 24 * 3600))
    }

    @Test func readsResetStampsInTheirStatedTimeZone() throws {
        let usage = try ClaudeProvider.parse(fixture("claude-usage.json"), now: now)

        // Sep 1, 2:29am in Asia/Kuala_Lumpur is Aug 31, 18:29 UTC.
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 1
        components.hour = 2
        components.minute = 29
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Kuala_Lumpur"))

        #expect(usage.limits[0].resetAt == calendar.date(from: components))
        #expect(usage.limits[1].resetAt != nil)
    }

    /// The narrative around the quota lines changes freely; only the
    /// `Current …:` lines are contractual.
    @Test func ignoresTheRestOfTheReport() {
        let limits = ClaudeUsageReport.parse(
            """
            You are currently using your subscription to power your Claude Code usage

            Current session: 12% used · resets Sep 1 at 2:29am (Asia/Kuala_Lumpur)

            What's contributing to your limits usage?
            Last 24h · 163 requests · 2 sessions
              79% of your usage was at >150k context
              Top skills: /peekaboo 11%
            """,
            now: now
        )
        #expect(limits.map(\.id) == ["session"])
        #expect(limits[0].usedPercent == 12)
    }

    @Test func readsAnExtraModelSpecificWindow() {
        let limits = ClaudeUsageReport.parse(
            """
            Current session: 36% used · resets Sep 1 at 2:29am (Asia/Kuala_Lumpur)
            Current week (all models): 5% used · resets Sep 6 at 10:59pm (Asia/Kuala_Lumpur)
            Current week (Opus): 22% used · resets Sep 6 at 10:59pm (Asia/Kuala_Lumpur)
            """,
            now: now
        )
        #expect(limits.map(\.name) == ["Session", "Weekly", "Week (Opus)"])
        #expect(limits.map(\.id) == ["session", "week-all-models", "week-opus"])
        #expect(limits[2].usedPercent == 22)
    }

    /// A reset landing on the hour drops its minutes.
    @Test func readsAResetWithNoMinutes() throws {
        let limits = ClaudeUsageReport.parse(
            "Current week (all models): 6% used · resets Sep 6 at 11pm (Asia/Kuala_Lumpur)",
            now: now
        )
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 6
        components.hour = 23
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Kuala_Lumpur"))

        #expect(limits.count == 1)
        #expect(limits[0].resetAt == calendar.date(from: components))
    }

    /// A percentage is still worth showing when the reset stamp is unreadable.
    @Test func keepsThePercentageWhenTheResetCannotBeParsed() {
        let limits = ClaudeUsageReport.parse("Current session: 40% used · resets soon", now: now)
        #expect(limits.count == 1)
        #expect(limits[0].usedPercent == 40)
        #expect(limits[0].resetAt == nil)
    }

    @Test func handlesALineWithNoResetAtAll() {
        let limits = ClaudeUsageReport.parse("Current session: 7% used", now: now)
        #expect(limits.map(\.usedPercent) == [7])
    }

    /// An API-key account gets a report with no quota lines in it.
    @Test func reportsUnavailableForAnAccountWithNoSubscriptionQuota() throws {
        #expect(throws: ProviderError.unavailable) {
            try ClaudeProvider.parse(fixture("claude-usage-api-key.json"), now: now)
        }
    }

    @Test func toleratesShellChatterBeforeTheJSON() throws {
        let noisy = "zoxide: configuration issue\nsome other warning\n" + (try fixture("claude-usage.json"))
        let usage = try ClaudeProvider.parse(noisy, now: now)
        #expect(usage.limits.count == 2)
    }

    /// The usage report says nothing about which plan the account is on, so the
    /// badge comes from `claude auth status` instead.
    @Test func carriesThePlanWhenOneIsKnown() throws {
        let usage = try ClaudeProvider.parse(fixture("claude-usage.json"), plan: "Pro", now: now)
        #expect(usage.plan == "Pro")
    }

    @Test func hasNoPlanWhenNoneCouldBeRead() throws {
        let usage = try ClaudeProvider.parse(fixture("claude-usage.json"), now: now)
        #expect(usage.plan == nil)
    }

    @Test func reportsInvalidResponseForGarbage() {
        #expect(throws: ProviderError.invalidResponse) {
            try ClaudeProvider.parse("not json at all", now: now)
        }
    }

    @Test func reportsInvalidResponseWhenTheCLIReportsAnError() {
        #expect(throws: ProviderError.invalidResponse) {
            try ClaudeProvider.parse(#"{"is_error":true,"result":"boom"}"#, now: now)
        }
    }
}
