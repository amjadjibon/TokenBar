import Foundation
import Testing
@testable import TokenBar

struct NotificationPlannerTests {
    private let window = Date(timeIntervalSince1970: 1_788_188_505)
    private let nextWindow = Date(timeIntervalSince1970: 1_788_206_505)

    private func settings(
        thresholds: Set<Int> = [20, 10],
        notifyOnReset: Bool = true
    ) -> AppSettings {
        var settings = AppSettings()
        settings.warningThresholds = thresholds
        settings.notifyOnReset = notifyOnReset
        return settings
    }

    private func usage(remaining: Double, resetAt: Date?) -> ProviderUsage {
        ProviderUsage(
            provider: .claude,
            limits: [UsageLimit(id: "seven_day", name: "Weekly", remainingPercent: remaining, resetAt: resetAt)]
        )
    }

    @Test func staysQuietAboveEveryThreshold() {
        var planner = NotificationPlanner()
        let notices = planner.plan(
            usage: usage(remaining: 45, resetAt: window),
            previous: nil,
            settings: settings()
        )
        #expect(notices.isEmpty)
    }

    @Test func warnsOnceWhenAThresholdIsCrossed() {
        var planner = NotificationPlanner()
        let notices = planner.plan(
            usage: usage(remaining: 18, resetAt: window),
            previous: nil,
            settings: settings()
        )
        #expect(notices.count == 1)
        #expect(notices[0].title == "Claude quota low")
        #expect(notices[0].body == "Weekly is below 20% remaining.")
    }

    @Test func doesNotRepeatTheSameWarningWithinAWindow() {
        var planner = NotificationPlanner()
        let state = usage(remaining: 18, resetAt: window)
        _ = planner.plan(usage: state, previous: nil, settings: settings())
        let second = planner.plan(usage: state, previous: state, settings: settings())
        #expect(second.isEmpty)
    }

    /// Dropping past 20% then past 10% should say "10%", not repeat "20%".
    @Test func announcesOnlyTheTightestCrossedThreshold() {
        var planner = NotificationPlanner()
        let first = usage(remaining: 18, resetAt: window)
        _ = planner.plan(usage: first, previous: nil, settings: settings())

        let second = usage(remaining: 8, resetAt: window)
        let notices = planner.plan(usage: second, previous: first, settings: settings())
        #expect(notices.map(\.body) == ["Weekly is below 10% remaining."])
    }

    @Test func ignoresThresholdsTheUserTurnedOff() {
        var planner = NotificationPlanner()
        let notices = planner.plan(
            usage: usage(remaining: 8, resetAt: window),
            previous: nil,
            settings: settings(thresholds: [5])
        )
        #expect(notices.isEmpty)
    }

    @Test func warnsAgainInTheNextWindow() {
        var planner = NotificationPlanner()
        let first = usage(remaining: 18, resetAt: window)
        _ = planner.plan(usage: first, previous: nil, settings: settings())

        let second = usage(remaining: 15, resetAt: nextWindow)
        let notices = planner.plan(usage: second, previous: first, settings: settings())
        #expect(notices.contains { $0.title == "Claude quota low" })
    }

    @Test func announcesAResetForAQuotaTheUserWasWarnedAbout() {
        var planner = NotificationPlanner()
        let low = usage(remaining: 8, resetAt: window)
        _ = planner.plan(usage: low, previous: nil, settings: settings())

        let reset = usage(remaining: 100, resetAt: nextWindow)
        let notices = planner.plan(usage: reset, previous: low, settings: settings())
        #expect(notices.map(\.title) == ["Claude quota reset"])
        #expect(notices[0].body == "Your Weekly quota has reset.")
    }

    /// Otherwise every provider would chime every few hours.
    @Test func staysQuietOnAResetTheUserWasNeverWarnedAbout() {
        var planner = NotificationPlanner()
        let healthy = usage(remaining: 70, resetAt: window)
        _ = planner.plan(usage: healthy, previous: nil, settings: settings())

        let reset = usage(remaining: 100, resetAt: nextWindow)
        let notices = planner.plan(usage: reset, previous: healthy, settings: settings())
        #expect(notices.isEmpty)
    }

    @Test func respectsTheResetNotificationSetting() {
        var planner = NotificationPlanner()
        let options = settings(notifyOnReset: false)
        let low = usage(remaining: 8, resetAt: window)
        _ = planner.plan(usage: low, previous: nil, settings: options)

        let reset = usage(remaining: 100, resetAt: nextWindow)
        #expect(planner.plan(usage: reset, previous: low, settings: options).isEmpty)
    }

    @Test func ignoresLimitsWithNoPercentage() {
        var planner = NotificationPlanner()
        let unknown = ProviderUsage(
            provider: .codex,
            limits: [UsageLimit(id: "x", name: "X", resetAt: window)]
        )
        #expect(planner.plan(usage: unknown, previous: nil, settings: settings()).isEmpty)
    }
}
