import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openSettings) private var openSettings

    /// Beyond this the provider list scrolls. Chosen so the panel stays well
    /// short of the screen even on a laptop display, however many providers are
    /// enabled.
    private static let maxListHeight: CGFloat = 420

    @State private var listHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 10)

            Divider()
            providerList
            Divider()

            footer
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .frame(width: 280)
    }

    /// Header and footer stay pinned; only the providers scroll, so Refresh and
    /// Quit are always reachable.
    private var providerList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if state.visibleProviders.isEmpty {
                    Text("No providers enabled.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(state.visibleProviders) { provider in
                        ProviderSection(provider: provider, state: state.states[provider])
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
        }
        // Sized to the content until it would outgrow the cap, so a short list
        // does not leave the panel padded with empty space.
        .frame(height: min(listHeight == 0 ? Self.maxListHeight : listHeight, Self.maxListHeight))
        .scrollBounceBehavior(.basedOnSize)
    }

    private var header: some View {
        HStack {
            Text("TokenBar")
                .font(.headline)
            Spacer()
            Button {
                Task { await state.refresh() }
            } label: {
                if state.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .disabled(state.isRefreshing)
            .keyboardShortcut("r")
            .help("Refresh all providers")
            .accessibilityLabel("Refresh")
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(state.lastRefresh.map { "Last updated \(QuotaFormat.clock($0))" } ?? "Not refreshed yet")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Settings…") {
                    openSettings()
                    // An accessory app is never frontmost, so the settings window
                    // would otherwise open behind whatever the user is using.
                    NSApp.activate()
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(",")

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("q")
            }
        }
    }
}
