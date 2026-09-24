import Foundation

/// Everything TokenBar writes lives under one local directory. Nothing leaves
/// the machine.
nonisolated enum AppPaths {
    static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "TokenBar", directoryHint: .isDirectory)
    }()

    static var settings: URL { root.appending(path: "settings.json") }
    static var cache: URL { root.appending(path: "cache", directoryHint: .isDirectory) }
    /// Last successful `ProviderUsage`, so the menu has something to show at launch.
    static func cachedUsage(_ provider: ProviderID) -> URL {
        cache.appending(path: "\(provider.rawValue).json")
    }

    static func createDirectories() throws {
        for directory in [root, cache] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
