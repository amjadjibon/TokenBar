import Foundation
import OSLog

/// Append-only usage log. Nothing reads it yet — it exists so that burn-rate
/// and usage charts have data to work with when they land.
actor HistoryStore {
    nonisolated struct Entry: Codable, Sendable, Equatable {
        let provider: ProviderID
        let limit: String
        let usedPercent: Double
        let timestamp: Date
    }

    private let logger = Logger(subsystem: TokenBarLog.subsystem, category: "storage")
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    func append(_ usage: ProviderUsage) {
        let entries = usage.limits.compactMap { limit -> Entry? in
            guard let used = limit.usedPercent else { return nil }
            return Entry(
                provider: usage.provider,
                limit: limit.id,
                usedPercent: used,
                timestamp: usage.updatedAt
            )
        }
        guard !entries.isEmpty else { return }

        do {
            try AppPaths.createDirectories()
            var lines = Data()
            for entry in entries {
                lines.append(try encoder.encode(entry))
                lines.append(0x0A)
            }
            try appendToLog(lines)
        } catch {
            logger.error("Could not append history: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func appendToLog(_ data: Data) throws {
        let url = AppPaths.historyLog
        if !FileManager.default.fileExists(atPath: url.path) {
            try data.write(to: url)
            return
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }
}
