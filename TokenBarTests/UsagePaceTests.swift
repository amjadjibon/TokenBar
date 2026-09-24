import Foundation
import Testing
@testable import TokenBar

struct UsagePaceTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func pace(remaining: Double, elapsedHours: Double) -> UsagePace? {
        let limit = UsageLimit(
            id: "five-hour",
            name: "5 hour",
            remainingPercent: remaining,
            windowStartAt: start,
            resetAt: start.addingTimeInterval(5 * 3600)
        )
        return UsagePace.evaluate(limit: limit, now: start.addingTimeInterval(elapsedHours * 3600))
    }

    @Test func eightyPercentRemainingAfterOneHourIsOnPace() {
        #expect(pace(remaining: 80, elapsedHours: 1) == .onPace)
    }

    @Test func lessThanEightyPercentRemainingAfterOneHourIsAbovePace() {
        #expect(pace(remaining: 60, elapsedHours: 1) == .above)
    }

    @Test func moreThanEightyPercentRemainingAfterOneHourIsBelowPace() {
        #expect(pace(remaining: 90, elapsedHours: 1) == .below)
    }

    @Test func ignoresAnUnknownOrExpiredWindow() {
        let reset = start.addingTimeInterval(5 * 3600)
        #expect(UsagePace.evaluate(
            limit: UsageLimit(id: "x", name: "X", usedPercent: 20, resetAt: reset),
            now: start
        ) == nil)
        #expect(UsagePace.evaluate(
            limit: UsageLimit(id: "x", name: "X", usedPercent: 20, windowStartAt: start, resetAt: reset),
            now: reset.addingTimeInterval(1)
        ) == nil)
    }
}
