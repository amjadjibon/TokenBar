import Foundation
import Testing
@testable import TokenBar

private nonisolated let plans: [(raw: String?, expected: String?)] = [
    ("pro", "Pro"),
    ("plus", "Plus"),
    ("max", "Max"),
    ("free", "Free"),
    ("team", "Team"),
    // Codex reports several plans in snake_case; `capitalized` alone would
    // leave the underscores in.
    ("edu_plus", "Edu Plus"),
    ("self_serve_business_prolite", "Self Serve Business Prolite"),
    ("ENTERPRISE", "Enterprise"),
    ("  pro  ", "Pro"),
    // A badge reading "Unknown" tells the user less than no badge at all.
    ("unknown", nil),
    ("", nil),
    (nil, nil),
]

struct PlanNameTests {
    @Test(arguments: plans)
    func formatsPlanIdentifiersForABadge(raw: String?, expected: String?) {
        #expect(PlanName.display(raw) == expected)
    }
}
