import Foundation

/// Loads sanitized provider responses from `TokenBarTests/Fixtures`.
///
/// Resolved from `#filePath` rather than a bundle so fixtures stay plain files
/// that can be diffed against real provider output.
enum Fixture {
    static func data(_ name: String) throws -> Data {
        let directory = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures", directoryHint: .isDirectory)
        return try Data(contentsOf: directory.appending(path: name))
    }
}
