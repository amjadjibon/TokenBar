import Foundation
import Testing
@testable import TokenBar

struct MenuBarTitleTests {
    private func usage(_ provider: ProviderID, remaining: Double) -> ProviderUsage {
        ProviderUsage(
            provider: provider,
            limits: [UsageLimit(id: "w", name: "Weekly", remainingPercent: remaining)]
        )
    }

    private let order: [ProviderID] = [.claude, .codex, .grok, .antigravity]

    @Test func namesTheProviderHoldingTheTightestQuota() {
        let tightest = MenuBarTitle.tightest(
            among: order,
            usage: [
                .claude: usage(.claude, remaining: 62),
                .codex: usage(.codex, remaining: 15),
                .antigravity: usage(.antigravity, remaining: 90),
            ]
        )
        #expect(tightest?.provider == .codex)
        #expect(tightest?.remainingPercent == 15)
    }

    /// Two providers level would otherwise let the title flip between them
    /// every refresh.
    @Test func breaksTiesByProviderOrder() {
        let tied = MenuBarTitle.tightest(
            among: order,
            usage: [.claude: usage(.claude, remaining: 40), .codex: usage(.codex, remaining: 40)]
        )
        #expect(tied?.provider == .claude)
    }

    @Test func ignoresProvidersThatAreNotEnabled() {
        let tightest = MenuBarTitle.tightest(
            among: [.claude],
            usage: [.claude: usage(.claude, remaining: 62), .codex: usage(.codex, remaining: 3)]
        )
        #expect(tightest?.provider == .claude)
    }

    @Test func hasNoAnswerBeforeAnythingHasReported() {
        #expect(MenuBarTitle.tightest(among: order, usage: [:]) == nil)
    }

    @Test func rendersTheProviderTagAndPercentage() {
        #expect(MenuBarTitle.text(prefix: "CX", percent: 15, warning: false) == "CX 15%")
        #expect(MenuBarTitle.text(prefix: "CL", percent: 61.5, warning: false) == "CL 62%")
    }

    @Test func marksAWarningWithoutRelyingOnColour() {
        #expect(MenuBarTitle.text(prefix: "CX", percent: 9, warning: true) == "CX 9% ⚠")
    }

    @Test func fallsBackWhenNothingIsKnownYet() {
        #expect(MenuBarTitle.text(prefix: MenuBarTitle.unknownPrefix, percent: nil, warning: false) == "TB —")
    }

    /// Claude and Codex share a first letter, so single letters would collide.
    @Test func providerTagsAreDistinct() {
        let tags = ProviderID.allCases.map(\.abbreviation)
        #expect(tags == ["CL", "CX", "GK", "AG"])
        #expect(Set(tags).count == tags.count)
    }
}
