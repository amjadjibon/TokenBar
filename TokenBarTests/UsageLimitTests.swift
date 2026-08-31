import Foundation
import Testing
@testable import TokenBar

struct UsageLimitTests {
    @Test func derivesRemainingFromUsed() {
        let limit = UsageLimit(id: "weekly", name: "Weekly", usedPercent: 61.5)
        #expect(limit.usedPercent == 61.5)
        #expect(limit.remainingPercent == 38.5)
    }

    @Test func derivesUsedFromRemaining() {
        let limit = UsageLimit(id: "gemini", name: "Gemini", remainingPercent: 81)
        #expect(limit.usedPercent == 19)
        #expect(limit.remainingPercent == 81)
    }

    @Test func keepsBothWhenProviderReportsBoth() {
        let limit = UsageLimit(id: "x", name: "X", usedPercent: 30, remainingPercent: 70)
        #expect(limit.usedPercent == 30)
        #expect(limit.remainingPercent == 70)
    }

    @Test func leavesPercentagesUnknownWhenProviderReportsNeither() {
        let limit = UsageLimit(id: "x", name: "X", resetAt: Date())
        #expect(limit.usedPercent == nil)
        #expect(limit.remainingPercent == nil)
        #expect(limit.remainingFraction == nil)
    }

    static let outOfRange: [(input: Double, used: Double, remaining: Double)] = [
        (-10, 0, 100),
        (140, 100, 0),
    ]

    @Test(arguments: outOfRange)
    func clampsOutOfRangePercentages(input: Double, used: Double, remaining: Double) {
        let limit = UsageLimit(id: "x", name: "X", usedPercent: input)
        #expect(limit.usedPercent == used)
        #expect(limit.remainingPercent == remaining)
    }

    @Test func reportsTimeUntilReset() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let limit = UsageLimit(id: "x", name: "X", resetAt: now.addingTimeInterval(3600))
        #expect(limit.timeUntilReset(now: now) == 3600)
    }
}

struct ProviderUsageTests {
    private func usage(_ remaining: [Double], updatedAt: Date = Date()) -> ProviderUsage {
        ProviderUsage(
            provider: .claude,
            limits: remaining.enumerated().map {
                UsageLimit(id: "\($0.offset)", name: "L\($0.offset)", remainingPercent: $0.element)
            },
            updatedAt: updatedAt
        )
    }

    @Test func lowestRemainingIsTheBindingConstraint() {
        #expect(usage([72, 41, 88]).lowestRemainingPercent == 41)
    }

    @Test func lowestRemainingIsUnknownWithoutLimits() {
        #expect(usage([]).lowestRemainingPercent == nil)
    }

    static let ages: [(age: TimeInterval, expected: Freshness)] = [
        (60, .fresh),
        (9 * 60, .fresh),
        (11 * 60, .stale),
        (29 * 60, .stale),
        (31 * 60, .veryStale),
    ]

    @Test(arguments: ages)
    func classifiesSnapshotAge(age: TimeInterval, expected: Freshness) {
        let now = Date()
        let snapshot = usage([50], updatedAt: now.addingTimeInterval(-age))
        #expect(snapshot.freshness(now: now) == expected)
        #expect(snapshot.freshness(now: now).needsWarning == (expected != .fresh))
    }
}
