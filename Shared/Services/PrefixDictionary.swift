import Foundation

struct WordEntry: Equatable {
    let word: String
    let freq: Int
}

/// Frequency-ranked word list, indexed by 1- and 2-letter lowercase prefixes.
/// Modeled on Edge's `dictionary.ts` + `candidateGenerator.ts` — same shape,
/// trimmed list. Drop more entries here as needed; ranking by descending
/// frequency is what the beam decoder consumes.
enum PrefixDictionary {

    static let maxPerToken = 50

    /// Curated frequency list. Hand-picked to cover common short sentences
    /// and the canonical "the dog ran home" / "i want to make a prediction
    /// market research app" examples.
    private static let starter: [(String, Int)] = [
        // function words
        ("the", 22_000_000), ("of", 12_000_000), ("and", 11_000_000), ("to", 10_500_000),
        ("a", 10_000_000), ("in", 8_500_000), ("is", 5_500_000), ("it", 5_400_000),
        ("you", 5_300_000), ("that", 5_200_000), ("he", 4_900_000), ("was", 4_800_000),
        ("for", 4_700_000), ("on", 4_600_000), ("are", 4_500_000), ("as", 4_300_000),
        ("with", 4_200_000), ("his", 4_000_000), ("they", 3_900_000), ("i", 3_800_000),
        ("at", 3_700_000), ("be", 3_600_000), ("this", 3_500_000), ("have", 3_400_000),
        ("from", 3_300_000), ("or", 3_200_000), ("one", 3_100_000), ("had", 3_000_000),
        ("by", 2_900_000), ("but", 2_700_000), ("not", 2_650_000), ("what", 2_600_000),
        ("all", 2_550_000), ("were", 2_500_000), ("we", 2_450_000), ("when", 2_400_000),
        ("your", 2_350_000), ("can", 2_300_000), ("said", 2_250_000), ("there", 2_200_000),
        ("an", 2_100_000), ("each", 2_050_000), ("which", 2_000_000), ("she", 1_950_000),
        ("do", 1_900_000), ("how", 1_850_000), ("their", 1_800_000), ("if", 1_750_000),
        ("will", 1_700_000), ("up", 1_650_000), ("other", 1_600_000), ("about", 1_550_000),
        ("out", 1_500_000), ("many", 1_450_000), ("then", 1_400_000), ("them", 1_380_000),
        ("so", 1_330_000), ("some", 1_310_000), ("her", 1_290_000), ("would", 1_270_000),
        ("make", 1_500_000), ("like", 1_230_000), ("him", 1_210_000), ("into", 1_190_000),
        ("time", 1_170_000), ("has", 1_150_000), ("look", 1_130_000), ("two", 1_110_000),
        ("more", 1_090_000), ("go", 1_050_000), ("see", 1_030_000), ("number", 1_010_000),
        ("no", 990_000), ("way", 970_000), ("could", 950_000), ("people", 930_000),
        ("my", 910_000), ("than", 890_000), ("first", 870_000), ("been", 850_000),
        ("call", 830_000), ("who", 810_000), ("its", 790_000), ("now", 770_000),
        ("find", 750_000), ("long", 730_000), ("down", 710_000), ("day", 690_000),
        ("did", 670_000), ("get", 650_000), ("come", 630_000), ("made", 610_000),
        ("may", 590_000), ("part", 570_000), ("over", 550_000), ("new", 530_000),
        ("take", 490_000), ("only", 470_000), ("little", 450_000), ("work", 430_000),
        ("know", 410_000), ("place", 390_000), ("years", 370_000), ("live", 350_000),
        ("me", 340_000), ("back", 330_000), ("give", 320_000), ("most", 310_000),
        ("very", 300_000), ("after", 290_000), ("thing", 280_000), ("our", 270_000),
        ("just", 260_000), ("name", 250_000), ("good", 240_000), ("want", 1_700_000),
        ("went", 250_000), ("wait", 350_000), ("walk", 4_000), ("war", 1_400),
        ("man", 225_000), ("think", 220_000), ("say", 215_000), ("great", 210_000),
        ("where", 205_000), ("help", 200_000), ("much", 190_000), ("before", 185_000),
        ("right", 175_000), ("too", 170_000), ("old", 160_000), ("any", 155_000),
        ("same", 150_000), ("tell", 145_000), ("ran", 480), ("home", 64_000),
        ("dog", 4_350), ("cat", 8_000), ("running", 9_000), ("read", 72_000),

        // domain words for predictive examples
        ("prediction", 30_000), ("market", 40_000), ("research", 25_000),
        ("app", 28_000), ("apps", 9_000), ("application", 8_000), ("apple", 4_000),
        ("data", 22_000), ("analysis", 6_000), ("report", 6_500), ("product", 11_000),
        ("business", 15_000), ("software", 7_000), ("code", 14_000), ("function", 5_000),

        // common pronouns/short fillers needed for natural sentences
        ("us", 62_000), ("am", 200_000), ("hi", 50_000), ("hello", 60_000),
        ("hey", 30_000), ("yes", 440), ("yeah", 20_000), ("ok", 10_000), ("okay", 8_000),

        // examples from the spec
        ("ate", 8_000), ("ant", 1_000), ("around", 116_000),
        ("brown", 1_700), ("quick", 1_800), ("fox", 2_000),
    ]

    /// Prefix → entries (already sorted by descending frequency).
    private static let index: [String: [WordEntry]] = build()

    /// Synthetic frequency assigned to words found only in
    /// /usr/share/dict/words (no real corpus frequency available). Below
    /// the obscurity threshold so they get penalised vs. real common
    /// words, but above zero so they're reachable.
    private static let systemDictFreq = 50

    private static func build() -> [String: [WordEntry]] {
        var dedup: [String: Int] = [:]

        // Tier 1: the curated baseline (kept for project-specific words
        // like "prediction market research app" that the AI examples lean
        // on heavily).
        for (w, f) in starter {
            let k = w.lowercased()
            dedup[k] = max(dedup[k] ?? 0, f)
        }
        // Tier 2: top-10k from Norvig's Google n-gram dump. This is the
        // bulk of real common-English vocabulary with accurate ranking.
        for (w, f) in NorvigTop10k.entries {
            let k = w.lowercased()
            dedup[k] = max(dedup[k] ?? 0, f)
        }
        // Tier 3: /usr/share/dict/words on macOS — ~235k entries, no
        // frequency info. Anything still missing gets a synthetic low
        // freq so it's reachable but ranks below corpus-known words.
        for w in loadSystemWordList() {
            if dedup[w] == nil {
                dedup[w] = systemDictFreq
            }
        }

        let entries = dedup
            .map { WordEntry(word: $0.key, freq: $0.value) }
            .sorted { $0.freq > $1.freq }

        var byPrefix: [String: [WordEntry]] = [:]
        for entry in entries {
            let w = entry.word
            guard !w.isEmpty else { continue }
            let p1 = String(w.first!)
            byPrefix[p1, default: []].append(entry)
            if w.count >= 2 {
                let p2 = String(w.prefix(2))
                byPrefix[p2, default: []].append(entry)
            }
        }
        return byPrefix
    }

    private static func loadSystemWordList() -> [String] {
        let path = "/usr/share/dict/words"
        guard let data = try? String(contentsOfFile: path, encoding: .utf8) else {
            return []
        }
        var out: [String] = []
        out.reserveCapacity(250_000)
        for line in data.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            // Pure lowercase alphabetic only, length 2..20 — skips proper
            // nouns, abbreviations, and oddities (the system list has a
            // surprising amount of weirdness).
            if trimmed.count >= 2, trimmed.count <= 20,
               trimmed.allSatisfy({ $0.isLetter && $0.isASCII }) {
                out.append(trimmed)
            }
        }
        return out
    }

    /// Flat frequency lookup (1 if unknown — never 0 so log(freq+1) doesn't trap).
    static func frequency(of word: String) -> Int {
        // Bucket scan is fine since the dictionary is tiny.
        let w = word.lowercased()
        guard !w.isEmpty else { return 1 }
        let p1 = String(w.first!)
        return index[p1]?.first(where: { $0.word == w })?.freq ?? 1
    }

    /// True if `word` is itself a recognised English word with non-trivial
    /// frequency. The shorthand detector uses this to short-circuit when
    /// the run before `.` is already a real word (e.g. "want.", "people.")
    /// so normal writing isn't transformed.
    static func isCommonWord(_ word: String) -> Bool {
        frequency(of: word) >= 1000
    }

    /// Up-to-`max` candidates for a lowercase prefix (1 or 2 letters),
    /// sorted by descending frequency. Unknown prefixes pass through as a
    /// single literal so the sentence still reconstructs end-to-end.
    static func candidates(forPrefix prefix: String, max: Int = maxPerToken) -> [String] {
        let p = prefix.lowercased()
        let bucket = index[p] ?? []
        if bucket.isEmpty { return [p] }
        return Array(bucket.prefix(max).map(\.word))
    }
}
