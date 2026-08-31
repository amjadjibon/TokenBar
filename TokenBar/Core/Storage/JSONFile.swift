import Foundation

/// Small helpers for the JSON-on-disk persistence the MVP uses.
nonisolated enum JSONFile {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Decodes JSON printed by a CLI.
    ///
    /// Shell start-up files can print before the command's own output, so the
    /// whole string is tried first (which also covers pretty-printed JSON), then
    /// the last line that parses on its own.
    static func decodeCommandOutput<T: Decodable>(
        _ type: T.Type,
        from output: String,
        using decoder: JSONDecoder = decoder
    ) -> T? {
        if let whole = try? decoder.decode(type, from: Data(output.utf8)) {
            return whole
        }
        return output
            .split(separator: "\n")
            .reversed()
            .lazy
            .compactMap { try? decoder.decode(type, from: Data($0.utf8)) }
            .first
    }

    static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try decoder.decode(type, from: Data(contentsOf: url))
    }

    /// Writes via a temporary file so a concurrent reader never sees a half-written file.
    static func write(_ value: some Encodable, to url: URL) throws {
        let data = try encoder.encode(value)
        let temporary = url.deletingLastPathComponent()
            .appending(path: ".\(url.lastPathComponent).tmp")
        try data.write(to: temporary, options: .atomic)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
    }
}
