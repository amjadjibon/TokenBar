import SwiftUI

@main
struct TokenBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state = AppState()

    init() {
        delegate.state = state
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(state)
        } label: {
            // A label needs something to draw, so icon-only mode uses a glyph
            // rather than an empty string.
            if state.settings.menuBarDisplay == .iconOnly {
                Image(systemName: state.isWarning
                    ? "gauge.with.dots.needle.bottom.0percent"
                    : "gauge.with.dots.needle.67percent")
            } else {
                Text(state.menuBarTitle)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(state)
        }
    }
}
