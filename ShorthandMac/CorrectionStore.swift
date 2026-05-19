import Foundation

/// Per-expansion learning record. Written every time the user accepts an
/// expansion (via timeout, swap, or low-confidence pick) and every time
/// they undo. Future expansion requests pull the N most recent records
/// matching the same compressed input — or the same recent context — as
/// few-shot examples.
struct CorrectionRecord: Codable, Equatable {
    let compressedInput: String
    let generatedSentence: String
    let finalUserSentence: String
    let confidence: Double
    let alternatives: [String]
    let pickedAlternative: String?
    let rejectedAlternatives: [String]
    let contextBefore: String
    let contextAfter: String
    let appName: String?
    let timestamp: Date
}

/// JSON-backed store under `~/Library/Application Support/Lazily/`.
/// Append-only on disk; in-memory cache is loaded once at startup.
@MainActor
final class CorrectionStore {

    private(set) var records: [CorrectionRecord] = []
    private let storeURL: URL?
    private let maxKept: Int

    init(storeURL: URL? = CorrectionStore.defaultStoreURL(), maxKept: Int = 500) {
        self.storeURL = storeURL
        self.maxKept = maxKept
        self.records = Self.load(from: storeURL)
    }

    /// Append a record and persist (best-effort).
    func record(_ rec: CorrectionRecord) {
        records.insert(rec, at: 0)
        if records.count > maxKept {
            records = Array(records.prefix(maxKept))
        }
        persist()
    }

    /// Returns the most-recent records that are most relevant to a new
    /// compressed input. Heuristic: exact-match compressed input first,
    /// then any record from the same app, then most-recent overall.
    /// Caps at `limit`.
    func relevant(forCompressed compressed: String,
                  appName: String?,
                  limit: Int = 5) -> [(compressed: String, final: String)] {
        var seenCompressed = Set<String>()
        var picked: [CorrectionRecord] = []

        for r in records where r.compressedInput == compressed && !seenCompressed.contains(r.compressedInput) {
            picked.append(r)
            seenCompressed.insert(r.compressedInput)
            if picked.count >= limit { break }
        }
        if picked.count < limit, let app = appName {
            for r in records where r.appName == app && !seenCompressed.contains(r.compressedInput) {
                picked.append(r)
                seenCompressed.insert(r.compressedInput)
                if picked.count >= limit { break }
            }
        }
        if picked.count < limit {
            for r in records where !seenCompressed.contains(r.compressedInput) {
                picked.append(r)
                seenCompressed.insert(r.compressedInput)
                if picked.count >= limit { break }
            }
        }
        return picked.map { ($0.compressedInput, $0.finalUserSentence) }
    }

    // MARK: - Disk

    nonisolated static func defaultStoreURL() -> URL? {
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = support.appendingPathComponent("Lazily", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("corrections.json")
    }

    nonisolated private static func load(from url: URL?) -> [CorrectionRecord] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([CorrectionRecord].self, from: data)) ?? []
    }

    private func persist() {
        guard let url = storeURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(records) else { return }
        // Best-effort atomic write.
        try? data.write(to: url, options: .atomic)
    }
}
