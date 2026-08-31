import Foundation
import Testing
@testable import TokenBar

struct PlanLabelTests {
    private func settings(_ labels: [ProviderID: String]) -> AppSettings {
        var settings = AppSettings()
        settings.planLabels = labels
        return settings
    }

    @Test func fallsBackToWhatTheProviderReported() {
        #expect(settings([:]).planLabel(for: .codex, reported: "Plus") == "Plus")
    }

    @Test func showsNothingWhenNobodyKnowsThePlan() {
        #expect(settings([:]).planLabel(for: .antigravity, reported: nil) == nil)
    }

    /// The point of the field: a provider that reports no plan can still be
    /// badged.
    @Test func suppliesAPlanTheProviderCannotReport() {
        let labels = settings([.antigravity: "Google AI Pro"])
        #expect(labels.planLabel(for: .antigravity, reported: nil) == "Google AI Pro")
    }

    /// The user knows their own subscription, so what they typed wins.
    @Test func aTypedLabelOverridesTheReportedOne() {
        let labels = settings([.codex: "Business"])
        #expect(labels.planLabel(for: .codex, reported: "Plus") == "Business")
    }

    @Test func labelsAreScopedToTheirOwnProvider() {
        let labels = settings([.claude: "Max"])
        #expect(labels.planLabel(for: .claude, reported: nil) == "Max")
        #expect(labels.planLabel(for: .codex, reported: "Plus") == "Plus")
    }

    @Test(arguments: ["", "   ", "\t"])
    func blankLabelsAreIgnored(blank: String) {
        let labels = settings([.codex: blank])
        #expect(labels.planLabel(for: .codex, reported: "Plus") == "Plus")
        #expect(labels.planLabel(for: .codex, reported: nil) == nil)
    }

    @Test func surroundingWhitespaceIsTrimmedForDisplay() {
        let labels = settings([.antigravity: "  Google AI Pro  "])
        #expect(labels.planLabel(for: .antigravity, reported: nil) == "Google AI Pro")
    }

    /// Keyed by provider id so settings.json stays legible by hand.
    @Test func survivesASettingsRoundTrip() throws {
        let original = settings([.antigravity: "Google AI Pro", .claude: "Max"])
        let data = try JSONFile.encoder.encode(original)
        let restored = try JSONFile.decoder.decode(AppSettings.self, from: data)

        #expect(restored.planLabels == original.planLabels)
        #expect(String(decoding: data, as: UTF8.self).contains("\"antigravity\" : \"Google AI Pro\""))
    }
}
