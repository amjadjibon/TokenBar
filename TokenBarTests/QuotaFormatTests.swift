import Foundation
import Testing
@testable import TokenBar

struct QuotaFormatTests {
    private let now = Date(timeIntervalSince1970: 1_788_000_000)

    @Test func countsDownWhileTheResetIsWithinADay() {
        let reset = now.addingTimeInterval(2 * 3600 + 14 * 60)
        #expect(QuotaFormat.reset(reset, now: now) == "Resets in 2h 14m")
    }

    @Test func switchesToAWeekdayBeyondADay() throws {
        let reset = now.addingTimeInterval(3 * 24 * 3600)
        let text = try #require(QuotaFormat.reset(reset, now: now))
        #expect(text.hasPrefix("Resets "))
        #expect(!text.contains("in "))
    }

    @Test func switchesToADateBeyondAWeek() throws {
        let reset = now.addingTimeInterval(10 * 24 * 3600)
        let text = try #require(QuotaFormat.reset(reset, now: now))
        #expect(text.hasPrefix("Resets "))
    }

    @Test func handlesAPassedReset() {
        #expect(QuotaFormat.reset(now.addingTimeInterval(-60), now: now) == "Resetting now")
        #expect(QuotaFormat.reset(nil, now: now) == nil)
    }

    /// Every component rounds down so a countdown never appears to increase
    /// between two refreshes.
    static let durations: [(interval: TimeInterval, expected: String)] = [
        (30, "under a minute"),
        (90, "1m"),
        (3600, "1h"),
        (3660, "1h 1m"),
        (7 * 3600 + 59 * 60, "7h 59m"),
        (86_400, "1d"),
        (86_400 + 5 * 3600, "1d 5h"),
    ]

    @Test(arguments: durations)
    func formatsDurationsRoundingDown(interval: TimeInterval, expected: String) {
        #expect(QuotaFormat.duration(interval) == expected)
    }

    @Test func formatsPercentages() {
        #expect(QuotaFormat.percent(61.5) == "62%")
        #expect(QuotaFormat.percent(0) == "0%")
        #expect(QuotaFormat.percent(nil) == "—")
    }

    @Test func describesSnapshotAge() {
        #expect(QuotaFormat.age(now.addingTimeInterval(-30), now: now) == "Updated just now")
        #expect(QuotaFormat.age(now.addingTimeInterval(-37 * 60), now: now) == "Updated 37m ago")
        #expect(QuotaFormat.age(nil, now: now) == "Never updated")
    }
}
