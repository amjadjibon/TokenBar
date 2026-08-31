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

    private var tint: Color {
        guard let remainingPercent else { return .secondary }
        switch remainingPercent {
        case ..<10: return .red
        case ..<25: return .orange
        default: return .green
        }
    }

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
