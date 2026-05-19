import Foundation

/// Word-frequency lookup used by the local pipeline (segmenter + polisher).
/// Built on top of NorvigTop10k.entries, with a hand-curated set of virtual
/// entries for high-frequency texting / chat tokens that the Norvig corpus
/// (Google n-grams of literary English) under-weights. The frequencies are
/// only used relatively, so the exact magnitudes don't matter — only the
/// ratios.
enum LocalDictionary {

    /// Norvig totals + room for our virtual entries.
    static let totalFrequency: Double = {
        let raw = NorvigTop10k.entries.reduce(0) { $0 + $1.1 }
        return Double(raw) + virtualTotal
    }()

    /// All entries, lowercased word → frequency.
    ///
    /// Norvig's top-10k is sourced from Google web n-grams and includes
    /// a lot of programming / acronym / 1-2-letter noise that the
    /// segmenter would happily pick over real English words. We filter
    /// it: 1-2 letter words must be in `shortAllowlist`; specific
    /// junk tokens are explicitly blacklisted.
    static let frequencies: [String: Double] = {
        var m: [String: Double] = [:]
        for (w, f) in NorvigTop10k.entries {
            if w.count <= 2 && !shortAllowlist.contains(w) { continue }
            if blacklist.contains(w) { continue }
            m[w] = Double(f)
        }
        for (w, f) in virtualEntries {
            m[w] = Double(f)
        }
        return m
    }()

    /// 1-2 letter Norvig entries that are real English words (not just
    /// acronyms / programming junk that snuck into the web corpus).
    /// Virtual shorthand entries (rn, hw, bc, ty, etc.) are added
    /// separately and don't have to live here.
    private static let shortAllowlist: Set<String> = [
        // 1-letter
        "a", "i",
        // 2-letter common English words
        "am", "an", "as", "at", "ax",
        "be", "by",
        "do",
        "go",
        "he", "hi",
        "if", "in", "is", "it",
        "me", "my",
        "no",
        "of", "oh", "ok", "on", "or", "ow", "ox",
        "pi",
        "so",
        "to",
        "up", "us",
        "we", "ya",
    ]

    /// Multi-letter Norvig entries that displace better English
    /// segmentations. Mostly programming jargon ("goto" beats "go to";
    /// "div" sometimes beats "did"; "html" sneaks in).
    private static let blacklist: Set<String> = [
        "goto",
        "html", "css", "json", "xml", "url", "uri",
        "var", "func", "const",
        "src", "tmp",
        "nbsp",
    ]

    /// Plain membership test.
    static func contains(_ word: String) -> Bool {
        frequencies[word.lowercased()] != nil
    }

    /// log10(freq / total). For unknowns, return a length-penalized
    /// floor — longer unknown strings are exponentially less likely than
    /// short ones, which matches Norvig's classic spell-corrector trick.
    static func logProb(_ word: String) -> Double {
        let key = word.lowercased()
        if let f = frequencies[key] {
            return log10(f / totalFrequency)
        }
        // Unknown — `10 / (N * 10^len)`, so cost grows with length.
        let len = max(1, word.count)
        return log10(10.0 / (totalFrequency * pow(10.0, Double(len))))
    }

    // MARK: - Virtual entries

    private static let virtualEntries: [(String, Int)] = [
        // Contractions without the apostrophe (very common in chat).
        ("im", 60_000_000),
        ("ive", 12_000_000),
        ("ill", 10_000_000),
        ("dont", 30_000_000),
        ("doesnt", 8_000_000),
        ("didnt", 12_000_000),
        ("wont", 8_000_000),
        ("wouldnt", 4_000_000),
        ("cant", 12_000_000),
        ("cannot", 6_000_000),
        ("couldnt", 4_000_000),
        ("shouldnt", 3_000_000),
        ("isnt", 6_000_000),
        ("arent", 4_000_000),
        ("wasnt", 5_000_000),
        ("werent", 3_000_000),
        ("hasnt", 3_000_000),
        ("havent", 5_000_000),
        ("hadnt", 2_000_000),
        ("mustnt", 1_000_000),
        ("youre", 12_000_000),
        ("youve", 6_000_000),
        ("youll", 4_000_000),
        ("youd", 3_000_000),
        ("theyre", 8_000_000),
        ("theyve", 4_000_000),
        ("theyll", 3_000_000),
        ("theyd", 2_000_000),
        ("were", 30_000_000),
        ("weve", 4_000_000),
        ("well", 25_000_000),
        ("wed", 5_000_000),
        ("hes", 8_000_000),
        ("shes", 7_000_000),
        ("its", 30_000_000),
        ("thats", 15_000_000),
        ("whats", 10_000_000),
        ("wheres", 4_000_000),
        ("whens", 3_000_000),
        ("hows", 4_000_000),
        ("theres", 6_000_000),
        ("heres", 5_000_000),
        ("whos", 4_000_000),
        ("lets", 6_000_000),
        ("aint", 3_000_000),
        ("yall", 2_000_000),
        ("gonna", 4_000_000),
        ("wanna", 3_000_000),
        ("gotta", 2_000_000),
        ("kinda", 2_000_000),
        ("sorta", 1_000_000),
        // Texting shorthand — the segmenter accepts them as words; the
        // ShorthandTokenExpander rewrites them into their full meaning
        // before polishing.
        ("tmr", 5_000_000),
        ("tmrw", 5_000_000),
        ("tmrrw", 3_000_000),
        ("yest", 3_000_000),
        ("rn", 8_000_000),
        ("hw", 5_000_000),
        ("hwy", 1_500_000),
        ("bc", 5_000_000),
        ("bcz", 3_000_000),
        ("cuz", 3_000_000),
        ("bday", 3_000_000),
        ("idk", 6_000_000),
        ("idc", 3_000_000),
        ("imo", 4_000_000),
        ("imho", 2_000_000),
        ("iirc", 1_500_000),
        ("brb", 3_000_000),
        ("btw", 5_000_000),
        ("fyi", 4_000_000),
        ("lmk", 5_000_000),
        ("ttyl", 2_000_000),
        ("tbh", 4_000_000),
        ("smh", 2_000_000),
        ("lol", 8_000_000),
        ("lmao", 3_000_000),
        ("omw", 3_000_000),
        ("nvm", 2_000_000),
        ("plz", 4_000_000),
        ("pls", 4_000_000),
        ("thx", 4_000_000),
        ("ty", 5_000_000),
        ("yw", 2_000_000),
        ("np", 4_000_000),
        ("ppl", 3_000_000),
        ("abt", 2_000_000),
        ("msg", 3_000_000),
        ("msgs", 1_500_000),
        ("prob", 3_000_000),
        ("def", 3_000_000),
        ("rly", 3_000_000),
        ("smth", 2_000_000),
        ("nthg", 1_500_000),
        ("frnd", 1_500_000),
        ("frnds", 1_500_000),
        ("schl", 1_500_000),
        ("sch", 2_000_000),
        ("ofc", 2_000_000),
        ("ily", 1_500_000),
        ("ur", 3_000_000),
        ("u", 5_000_000),
        ("w", 1_000_000),
        ("wo", 1_000_000),
        ("alot", 3_000_000),
    ]

    private static let virtualTotal: Double = {
        Double(virtualEntries.reduce(0) { $0 + $1.1 })
    }()
}
