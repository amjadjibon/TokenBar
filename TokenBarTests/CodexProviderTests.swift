import Foundation
import Testing
@testable import TokenBar

struct CodexProviderTests {
    private func decode(_ fixture: String) throws -> CodexProtocol.RateLimitsResult {
        try JSONDecoder().decode(CodexProtocol.RateLimitsResult.self, from: Fixture.data(fixture))
    }

    @Test func mapsPrimaryAndSecondaryWindows() throws {
        let limits = try decode("codex-rate-limits.json").usageLimits()

        #expect(limits.count == 2)
        #expect(limits[0].id == "codex.primary")
        #expect(limits[0].name == "5 hour")
        #expect(limits[0].usedPercent == 67)
        #expect(limits[0].remainingPercent == 33)
        #expect(limits[0].resetAt == Date(timeIntervalSince1970: 1_788_188_505))
        #expect(limits[0].windowStartAt == Date(timeIntervalSince1970: 1_788_188_505 - 5 * 3600))

        #expect(limits[1].name == "Weekly")
        #expect(limits[1].usedPercent == 10)
        #expect(limits[1].remainingPercent == 90)
    }

    @Test func readsThePlan() throws {
        #expect(try decode("codex-rate-limits.json").planType == "plus")
    }

    /// With one bucket the name is just the window; with several, each window
    /// has to say which bucket it belongs to.
    @Test func namesBucketsOnlyWhenThereIsMoreThanOne() throws {
        let limits = try decode("codex-rate-limits-multi-bucket.json").usageLimits()
        #expect(limits.map(\.name) == ["Codex 5 hour", "Code review Daily"])
        #expect(limits.map(\.id) == ["codex.primary", "review.primary"])
    }

    @Test func fallsBackToTheSingleBucketViewWhenTheMapIsAbsent() throws {
        let json = Data("""
        {"rateLimits":{"limitId":"codex","primary":{"usedPercent":50,"windowDurationMins":300}}}
        """.utf8)
        let result = try JSONDecoder().decode(CodexProtocol.RateLimitsResult.self, from: json)
        let limits = result.usageLimits()
        #expect(limits.count == 1)
        #expect(limits[0].name == "5 hour")
        #expect(limits[0].resetAt == nil)
    }

    static let windowNames: [(minutes: Int, expected: String)] = [
        (60, "Hourly"), (300, "5 hour"), (1440, "Daily"), (10080, "Weekly"),
        (43200, "Monthly"), (180, "3 hour"), (2880, "2 day"), (45, "45 min"),
    ]

    @Test(arguments: windowNames)
    func namesWindowsFromTheirDuration(minutes: Int, expected: String) throws {
        let json = Data("""
        {"rateLimits":{"limitId":"c","primary":{"usedPercent":1,"windowDurationMins":\(minutes)}}}
        """.utf8)
        let result = try JSONDecoder().decode(CodexProtocol.RateLimitsResult.self, from: json)
        #expect(result.usageLimits().first?.name == expected)
    }

    @Test func toleratesAWindowWithNoDuration() throws {
        let json = Data(#"{"rateLimits":{"limitId":"c","secondary":{"usedPercent":3}}}"#.utf8)
        let result = try JSONDecoder().decode(CodexProtocol.RateLimitsResult.self, from: json)
        #expect(result.usageLimits().map(\.name) == ["Secondary"])
    }
}
