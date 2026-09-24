import Foundation
import Testing
@testable import TokenBar

struct AntigravityProviderTests {
    private func fixture(_ name: String) throws -> String {
        try String(decoding: Fixture.data(name), as: UTF8.self)
    }

    @Test func keepsModelFamiliesAsSeparateBuckets() throws {
        let usage = try AntigravityProvider.parse(fixture("antigravity-usage.json"))

        #expect(usage.provider == .antigravity)
        #expect(usage.limits.map(\.id) == ["gemini-5h", "gemini-weekly", "3p-5h", "3p-weekly"])
        #expect(usage.limits.map(\.name) == [
            "Gemini 5 hour", "Gemini Weekly",
            "Claude and GPT 5 hour", "Claude and GPT Weekly",
        ])
    }

    /// Antigravity reports 0...1, not a percentage.
    @Test func convertsFractionsToPercentages() throws {
        let usage = try AntigravityProvider.parse(fixture("antigravity-usage.json"))
        let byID = Dictionary(uniqueKeysWithValues: usage.limits.map { ($0.id, $0) })

        #expect(byID["gemini-weekly"]?.remainingPercent == 81)
        #expect(byID["gemini-weekly"]?.usedPercent == 19)
        #expect(byID["3p-weekly"]?.remainingPercent == 100)
        #expect(byID["3p-5h"]?.remainingPercent == 7)
    }

    /// The family about to run out is the one that matters, so it must not be
    /// averaged away with the others.
    @Test func lowestRemainingIsTheTightestFamily() throws {
        let usage = try AntigravityProvider.parse(fixture("antigravity-usage.json"))
        #expect(usage.lowestRemainingPercent == 7)
    }

    @Test func readsResetTimes() throws {
        let usage = try AntigravityProvider.parse(fixture("antigravity-usage.json"))
        let fiveHour = try #require(usage.limits.first { $0.id == "gemini-5h" })
        #expect(fiveHour.resetAt == Date(timeIntervalSince1970: 1_788_203_928)) // 2026-08-31T19:18:48Z
        #expect(fiveHour.windowStartAt == fiveHour.resetAt?.addingTimeInterval(-5 * 3600))
    }

    @Test func namesWindowsFromTheBucketLabelWhenTheWindowFieldIsMissing() throws {
        let json = """
        {"status":"SUCCESS","command":{"name":"usage","data":{"groups":[{"name":"Gemini Models",
        "buckets":[{"id":"g","name":"Weekly Limit Remaining","remaining_fraction":0.5}]}]}}}
        """
        let usage = try AntigravityProvider.parse(json)
        #expect(usage.limits.map(\.name) == ["Gemini Weekly"])
    }

    @Test func reportsUnavailableWhenNoBucketsAreReported() {
        #expect(throws: ProviderError.unavailable) {
            try AntigravityProvider.parse(#"{"status":"SUCCESS","command":{"data":{"groups":[]}}}"#)
        }
    }

    @Test func reportsInvalidResponseForAFailedCommand() {
        #expect(throws: ProviderError.invalidResponse) {
            try AntigravityProvider.parse(#"{"status":"ERROR","command":{"data":{"groups":[]}}}"#)
        }
    }

    @Test func reportsInvalidResponseForGarbage() {
        #expect(throws: ProviderError.invalidResponse) {
            try AntigravityProvider.parse("not json at all")
        }
    }

    @Test func toleratesShellChatterBeforeTheJSON() throws {
        let noisy = "zoxide: configuration issue\n" + (try fixture("antigravity-usage.json"))
        #expect(try AntigravityProvider.parse(noisy).limits.count == 4)
    }
}
