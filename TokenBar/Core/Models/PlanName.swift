import Foundation

nonisolated enum PlanName {
    /// Turns a provider's raw plan identifier into something fit for a badge:
    /// `pro` → "Pro", `edu_plus` → "Edu Plus".
    ///
    /// A provider that reports "unknown" gets no badge at all — an empty space
    /// says the same thing more honestly than the word does.
    static func display(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.lowercased() != "unknown" else { return nil }

        return trimmed
            .split { $0 == "_" || $0 == "-" || $0 == " " }
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}
