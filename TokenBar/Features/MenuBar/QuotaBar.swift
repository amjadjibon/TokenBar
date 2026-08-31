import SwiftUI

/// Usage bar for one quota window.
///
/// Health is never signalled by colour alone — the percentage and a warning
/// glyph carry the same information as text.
struct QuotaBar: View {
    let remainingPercent: Double?

    private var fraction: Double {
        guard let remainingPercent else { return 0 }
        return min(max(remainingPercent / 100, 0), 1)
    }

    /// Green with half the quota or more left, yellow below that, red under 10%.
    /// Grey when the provider reported no percentage at all.
    static func tint(remainingPercent: Double?) -> Color {
        guard let remainingPercent else { return .secondary }
        switch remainingPercent {
        case ..<10: return .red
        case ..<50: return .yellow
        default: return .green
        }
    }

    private var tint: Color { Self.tint(remainingPercent: remainingPercent) }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(tint)
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}
