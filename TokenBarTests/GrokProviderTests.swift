import Foundation
import Testing
@testable import TokenBar

struct GrokProviderTests {
    @Test func parsesTheSharedWeeklyPool() throws {
        let result = try JSONDecoder().decode(
            GrokProtocol.BillingResult.self,
            from: Fixture.data("grok-billing-weekly.json")
        )
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let usage = try result.providerUsage(now: now)

        #expect(usage.provider == .grok)
        #expect(usage.plan == "SuperGrok Heavy")
        #expect(usage.updatedAt == now)
        #expect(usage.limits.count == 1)
        #expect(usage.limits[0].id == "weekly")
        #expect(usage.limits[0].name == "Weekly")
        #expect(usage.limits[0].usedPercent == 42.5)
        #expect(usage.limits[0].remainingPercent == 57.5)
        #expect(usage.limits[0].resetAt != nil)
        #expect(usage.limits[0].windowStartAt != nil)
    }

    @Test func supportsTheDeprecatedCreditShape() throws {
        let result = try JSONDecoder().decode(
            GrokProtocol.BillingResult.self,
            from: Fixture.data("grok-billing-legacy.json")
        )
        let usage = try result.providerUsage()

        #expect(usage.limits[0].name == "Monthly")
        #expect(usage.limits[0].usedPercent == 25)
        #expect(usage.limits[0].remainingPercent == 75)
    }

    @Test func rejectsBillingWithoutAUsableLimit() throws {
        let result = try JSONDecoder().decode(
            GrokProtocol.BillingResult.self,
            from: Data(#"{"config":{}}"#.utf8)
        )
        #expect(throws: ProviderError.unavailable) {
            try result.providerUsage()
        }
    }

    @Test func selectsTheOIDCCredentialWithoutExposingOtherFields() throws {
        let data = Data(
            #"{"https://accounts.x.ai/sign-in":{"key":"legacy","user_id":"old"},"https://auth.x.ai::client":{"key":"oidc-token","user_id":"user-1","email":"ignored@example.com"}}"#.utf8
        )
        let credential = try GrokProvider.credential(from: data)

        #expect(credential.key == "oidc-token")
        #expect(credential.userID == "user-1")
    }
}
