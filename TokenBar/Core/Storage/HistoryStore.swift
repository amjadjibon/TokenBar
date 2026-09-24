import Foundation
import OSLog

/// Append-only usage log. A reading is tied to its reset window so pace
/// estimates never compare usage across two different quota windows.
actor HistoryStore {
    nonisolated struct Entry: Codable, Sendable, Equatable {
        let provider: ProviderID
        let limit: String
        let usedPercent: Double
        let timestamp: Date
        let resetAt: Date?
    }

    private var entries: [Entry]?

    private let logger = Logger(subsystem: TokenBarLog.subsystem, category: "storage")
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    func observe(_ usage: ProviderUsage) -> [String: UsagePace] {
        loadIfNeeded()
        var pace: [String: UsagePace] = [:]
        let newEntries = usage.limits.compactMap { limit -> Entry? in
            guard let used = limit.usedPercent else { return nil }
            return Entry(
                provider: usage.provider,
                limit: limit.id,
                usedPercent: used,
                timestamp: usage.updatedAt,
                // The JSON log stores ISO-8601 dates to the second. Normalize
                // before matching so fractional provider times survive a restart.
                resetAt: limit.resetAt.map {
                    Date(timeIntervalSince1970: floor($0.timeIntervalSince1970))
                }
            )
        }

        for entry in newEntries {
            if let reset = entry.resetAt,
               reset > entry.timestamp,
               let baseline = entries?.last(where: {
                   $0.provider == entry.provider && $0.limit == entry.limit &&
                   $0.resetAt == reset &&
                   $0.timestamp <= entry.timestamp.addingTimeInterval(-15 * 60)
               }),
               let estimate = UsagePace.evaluate(
                   earlierUsed: baseline.usedPercent,
                   currentUsed: entry.usedPercent,
                   elapsed: entry.timestamp.timeIntervalSince(baseline.timestamp),
                   timeUntilReset: reset.timeIntervalSince(entry.timestamp)
               ) {
                pace[entry.limit] = estimate
            }
        }

        // The current reading is compared even when unchanged. Persist only
        // changes, while ensuring an old cache has a first window reading.
        let changes = newEntries.filter { entry in
            let latest = entries?.last { prior in
                prior.provider == entry.provider && prior.limit == entry.limit &&
                prior.resetAt == entry.resetAt
            }
            return latest?.usedPercent != entry.usedPercent
        }
        append(changes)
        return pace
    }

    private func loadIfNeeded() {
        guard entries == nil else { return }
        guard let data = try? Data(contentsOf: AppPaths.historyLog) else {
            entries = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = data.split(separator: 0x0A).compactMap {
            try? decoder.decode(Entry.self, from: Data($0))
        }
    }

    private func append(_ newEntries: [Entry]) {
        guard !newEntries.isEmpty else { return }

        do {
            try AppPaths.createDirectories()
            var lines = Data()
            for entry in newEntries {
                lines.append(try encoder.encode(entry))
                lines.append(0x0A)
            }
            try appendToLog(lines)
            entries?.append(contentsOf: newEntries)
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
