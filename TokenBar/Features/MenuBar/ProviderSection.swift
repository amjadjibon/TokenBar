import SwiftUI

struct ProviderSection: View {
    let provider: ProviderID
    let state: ProviderState?
    let plan: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if let usage = state?.usage, !usage.limits.isEmpty {
                ForEach(usage.limits) { limit in
                    LimitRow(limit: limit)
                }
                if usage.freshness().needsWarning {
                    Label(QuotaFormat.age(usage.updatedAt), systemImage: "clock.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if state?.error == nil {
                Text("No quota reported")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(provider.displayName)
                .font(.headline)
            if let plan {
                Text(plan)
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
            Spacer(minLength: 4)
        }

        if let error = state?.error {
            // Errors sit alongside the last good numbers rather than replacing them.
            Label(
                error.errorDescription ?? "Unable to refresh",
                systemImage: "exclamationmark.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
