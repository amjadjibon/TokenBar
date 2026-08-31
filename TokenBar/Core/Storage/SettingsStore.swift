import Foundation
import OSLog

/// Reads and writes `settings.json`. Missing or corrupt files fall back to
/// defaults rather than failing the launch.
@MainActor
@Observable
final class SettingsStore {
    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            save()
        }
    }

    private let logger = Logger(subsystem: TokenBarLog.subsystem, category: "storage")

    init() {
        settings = (try? JSONFile.read(AppSettings.self, from: AppPaths.settings)) ?? AppSettings()
    }

    private func save() {
        do {
            try AppPaths.createDirectories()
            try JSONFile.write(settings, to: AppPaths.settings)
        } catch {
            logger.error("Could not save settings: \(error.localizedDescription, privacy: .public)")
        }
    }
}
