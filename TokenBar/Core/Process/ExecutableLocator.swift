import Foundation
import OSLog

/// Finds provider CLIs on disk.
///
/// A GUI app inherits a bare `PATH` (`/usr/bin:/bin:/usr/sbin:/sbin`), which
/// misses Homebrew, nvm and `~/.local/bin` where these tools actually live. So
/// we ask the user's shell for its `PATH` once — using a fixed command with no
/// interpolation — and search that ourselves.
actor ExecutableLocator {
    static let shared = ExecutableLocator()

    private let logger = Logger(subsystem: TokenBarLog.subsystem, category: "process")
    private var cachedSearchPaths: [String]?
    private var cachedExecutables: [String: URL] = [:]

    func find(_ name: String) async -> URL? {
        if let cached = cachedExecutables[name] { return cached }

        let fileManager = FileManager.default
        for directory in await searchPaths() {
            let candidate = URL(filePath: directory).appending(path: name)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                cachedExecutables[name] = candidate
                logger.debug("Located \(name, privacy: .public)")
                return candidate
            }
        }
        logger.debug("Could not locate \(name, privacy: .public)")
        return nil
    }

    /// Forget cached lookups so a newly installed tool is picked up.
    func invalidate() {
        cachedSearchPaths = nil
        cachedExecutables.removeAll()
    }

    private func searchPaths() async -> [String] {
        if let cachedSearchPaths { return cachedSearchPaths }

        var paths = await loginShellPath()
        for fallback in Self.fallbackPaths where !paths.contains(fallback) {
            paths.append(fallback)
        }
        cachedSearchPaths = paths
        return paths
    }

    private func loginShellPath() async -> [String] {
        guard let shell = ProcessInfo.processInfo.environment["SHELL"] else { return [] }

        let process = Process()
        process.executableURL = URL(filePath: shell)
        // Interactive as well as login: version managers like nvm and pyenv put
        // their shims on PATH from `.zshrc`, which a login-only shell skips.
        process.arguments = ["-ilc", "printf %s \"$PATH\""]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            logger.warning("Could not read login shell PATH")
            return []
        }

        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()

        // Chatty rc files print before our command does, so only the last line
        // is the PATH.
        let output = String(decoding: data, as: UTF8.self)
        let path = output.split(separator: "\n").last.map(String.init) ?? output

        return path
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static let fallbackPaths = [
        "\(NSHomeDirectory())/.local/bin",
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
    ]
}
