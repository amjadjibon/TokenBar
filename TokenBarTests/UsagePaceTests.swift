import Foundation
import Testing
@testable import TokenBar

struct UsagePaceTests {
    @Test func showsAbovePaceWhenProjectedUsageExceedsTheQuota() {
        #expect(UsagePace.evaluate(
            earlierUsed: 20,
            currentUsed: 40,
            elapsed: 3600,
            timeUntilReset: 4 * 3600
        ) == .above)
    }

    @Test func showsWithinPaceWhenQuotaShouldLast() {
        #expect(UsagePace.evaluate(
            earlierUsed: 20,
            currentUsed: 25,
            elapsed: 3600,
            timeUntilReset: 4 * 3600
        ) == .within)
    }

    @Test func waitsForEnoughObservationTime() {
        #expect(UsagePace.evaluate(
            earlierUsed: 20,
            currentUsed: 40,
            elapsed: 5 * 60,
            timeUntilReset: 4 * 3600
        ) == nil)
    }

    @Test func ignoresExpiredWindowsAndProviderCorrections() {
        #expect(UsagePace.evaluate(
            earlierUsed: 30,
            currentUsed: 20,
            elapsed: 3600,
            timeUntilReset: 3600
        ) == nil)
        #expect(UsagePace.evaluate(
            earlierUsed: 20,
            currentUsed: 30,
            elapsed: 3600,
            timeUntilReset: 0
        ) == nil)
    }

    @Test func exhaustedQuotaIsAbovePace() {
        #expect(UsagePace.evaluate(
            earlierUsed: 100,
            currentUsed: 100,
            elapsed: 3600,
            timeUntilReset: 3600
        ) == .above)
    }
}
