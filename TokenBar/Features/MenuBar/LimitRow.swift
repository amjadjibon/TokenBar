import SwiftUI

struct LimitRow: View {
    let limit: UsageLimit
    let observedAt: Date

    private var isLow: Bool {
        (limit.remainingPercent ?? 100) < 20
    }

    private var pace: UsagePace? { UsagePace.evaluate(limit: limit, now: observedAt) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(limit.name)
                    .font(.callout)
                Spacer(minLength: 8)
                if isLow {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .imageScale(.small)
                }
                Text("\(QuotaFormat.percent(limit.usedPercent)) used")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            QuotaBar(remainingPercent: limit.remainingPercent)

            HStack(spacing: 6) {
                Text("\(QuotaFormat.percent(limit.remainingPercent)) remaining")
                if let reset = QuotaFormat.reset(limit.resetAt) {
                    Text("·")
                    Text(reset)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let pace {
                Text(pace.message)
                    .font(.caption)
                    .foregroundStyle(pace == .above ? .orange : .secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [
            limit.name,
            "\(QuotaFormat.percent(limit.remainingPercent)) remaining",
        ]
        if isLow { parts.append("low") }
        if let reset = QuotaFormat.reset(limit.resetAt) { parts.append(reset) }
        if let pace { parts.append(pace.message) }
        return parts.joined(separator: ", ")
    }
}
