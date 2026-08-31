import SwiftUI
import Testing
@testable import TokenBar

/// The band edges, where an off-by-one comparison would hide. Declared outside
/// the suite so the `@Test` macro can read it without crossing an actor.
private nonisolated let bands: [(remaining: Double, expected: Color)] = [
    (100, .green),
    (50, .green),   // half left is still healthy
    (49.9, .yellow),
    (10, .yellow),  // exactly 10 has not gone critical yet
    (9.9, .red),
    (0, .red),
]

@MainActor
struct QuotaBarTests {
    @Test(arguments: bands)
    func picksTheBandForRemainingQuota(remaining: Double, expected: Color) {
        #expect(QuotaBar.tint(remainingPercent: remaining) == expected)
    }

    @Test func staysNeutralWhenNoPercentageWasReported() {
        #expect(QuotaBar.tint(remainingPercent: nil) == .secondary)
    }
}
