import AppKit

/// Starts the refresh loop at launch.
///
/// A `MenuBarExtra` in `.window` style only builds its content when the menu is
/// opened, so the app cannot rely on the view to kick off refreshing — otherwise
/// the menu bar title would stay blank until first click and no notification
/// would ever fire in the background.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var state: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let state else { return }
        Task { await state.start() }
    }
}
