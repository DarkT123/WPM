import Foundation

/// Local-first correction memory. Mirrors Edge's `correctionMemory.ts`:
///
///   - **Exact pattern**: the compressed shorthand → corrected sentence
///     mapping. Repeating the same shorthand returns the prior accepted
///     correction verbatim.
///   - **Token boosts**: per `(prefix, word)` count, biases the beam scorer
///     toward previously-confirmed words.
///   - **Prefix successors**: per `(prev word, prefix → word)` count, the
///     strongest local signal — a single learned `(i, wa) → was` shifts
///     future predictions for the same prev/prefix even on unrelated
///     sentences.
///   - **Phrase memory** snapshot: persisted alongside so n-grams learned
///     from corrections survive relaunches.
///
/// All state is persisted to the App Group container as JSON.
final class CorrectionMemory {

    private static let schemaVersion = 1
    private static let fileName = "shorthand_corrections.json"

    private struct File: Codable {
        var version: Int
        var exactPatterns: [String: String]
        var wordBoosts: [String: [String: Int]]        // prefix → word → count
        var prefixSuccessors: [String: Int]            // "prev|prefix|word" → count
        var phraseSnapshot: PhraseMemory.Snapshot?
    }

    private var exact: [String: String] = [:]
    private var boosts: [String: [String: Int]] = [:]
    private var successors: [String: Int] = [:]

    private let storeURL: URL?
    private let phrases: PhraseMemory

    init(storeURL: URL? = CorrectionMemory.defaultStoreURL(), phrases: PhraseMemory) {
        self.storeURL = storeURL
        self.phrases = phrases
        load()
    }

    static func defaultStoreURL() -> URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedDefaults.suiteName)
        else { return nil }
        return container.appendingPathComponent(fileName)
    }

    // MARK: - Lookups

    func exactMatch(_ compressed: String) -> String? {
        exact[compressed.lowercased()]
    }

    /// Boost for (prefix token → word). 0 when nothing was ever learned.
    func wordBoost(prefix: String, word: String) -> Int {
        boosts[prefix.lowercased()]?[word.lowercased()] ?? 0
    }

    /// Strongest local correction signal: how many times have we seen this
    /// exact `(prev, prefix) → word` triple from accepted corrections?
    func prefixSuccessorBoost(prev: String, prefix: String, word: String) -> Int {
        successors[Self.successorKey(prev: prev, prefix: prefix, word: word)] ?? 0
    }

    // MARK: - Record

    /// Persist a correction. `tokens` is the segmentation the beam was
    /// originally given (e.g. `["i", "wa", "to", "ma"]`); `words` is the
    /// user's final accepted sentence split into matching word slots.
    /// Both must have the same count.
    func record(tokens: [String], words: [String]) {
        guard !tokens.isEmpty, tokens.count == words.count else { return }
        let ts = tokens.map { $0.lowercased() }
        let ws = words.map { $0.lowercased() }

        exact[ts.joined(separator: " ")] = ws.joined(separator: " ")

        for i in 0..<ts.count {
            let t = ts[i]
            let w = ws[i]
            boosts[t, default: [:]][w, default: 0] += 1
            let prev = i > 0 ? ws[i - 1] : ""
            let key = Self.successorKey(prev: prev, prefix: t, word: w)
            successors[key, default: 0] += 1
        }

        phrases.learn(ws)
        persist()
    }

    // MARK: - Persistence

    private static func successorKey(prev: String, prefix: String, word: String) -> String {
        "\(prev.lowercased())|\(prefix.lowercased())|\(word.lowercased())"
    }

    private func load() {
        guard let url = storeURL,
              let data = try? Data(contentsOf: url),
              let parsed = try? JSONDecoder().decode(File.self, from: data) else { return }
        guard parsed.version == Self.schemaVersion else {
            // Future schema bumps: wipe and start fresh. The user's correction
            // corpus is cheap to rebuild and stale entries from an older shape
            // would just confuse the decoder.
            return
        }
        exact = parsed.exactPatterns
        boosts = parsed.wordBoosts
        successors = parsed.prefixSuccessors
        if let snap = parsed.phraseSnapshot { phrases.restore(snap) }
    }

    private func persist() {
        guard let url = storeURL else { return }
        let file = File(
            version: Self.schemaVersion,
            exactPatterns: exact,
            wordBoosts: boosts,
            prefixSuccessors: successors,
            phraseSnapshot: phrases.snapshot()
        )
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Test hooks

    /// In-memory factory used by tests.
    static func ephemeral(phrases: PhraseMemory) -> CorrectionMemory {
        CorrectionMemory(storeURL: nil, phrases: phrases)
    }
}
