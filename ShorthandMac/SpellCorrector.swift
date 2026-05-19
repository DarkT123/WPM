import Foundation

/// Norvig's classic edit-distance-1 spell corrector, adapted to Swift.
/// For an unknown token, generate every string one edit away (deletion,
/// transposition, replacement, insertion), filter to those in
/// LocalDictionary, and pick the highest-frequency match.
///
/// Only operates on tokens of length ≥ 4 — short tokens (1-3 chars) are
/// more likely to be deliberate shorthand than typos, and edit-1 from
/// a 3-letter token reaches almost any common word, which produces
/// over-confident garbage. (e.g. "tdr" → "tar" / "the" / "tor" — none
/// of which we want.)
enum SpellCorrector {

    /// Minimum token length to attempt correction. Below this we assume
    /// the user typed shorthand on purpose.
    static let minLength = 4

    /// Returns the best edit-1 dictionary match if any, else nil.
    /// Always returns nil for tokens already in the dictionary (no
    /// correction needed).
    static func correct(_ token: String) -> String? {
        guard token.count >= minLength else { return nil }
        let lower = token.lowercased()
        if LocalDictionary.contains(lower) { return nil }

        let candidates = edits1(lower).filter { LocalDictionary.contains($0) }
        guard !candidates.isEmpty else { return nil }

        return candidates.max(by: { a, b in
            LocalDictionary.logProb(a) < LocalDictionary.logProb(b)
        })
    }

    /// All strings one edit away from `word`. ~250 candidates for a
    /// 5-letter word; trivially fast (microseconds).
    private static let alphabet: [Character] = Array("abcdefghijklmnopqrstuvwxyz")

    static func edits1(_ word: String) -> Set<String> {
        let chars = Array(word)
        var result = Set<String>()

        // Deletions
        for i in 0..<chars.count {
            var c = chars; c.remove(at: i)
            result.insert(String(c))
        }
        // Transpositions
        if chars.count >= 2 {
            for i in 0..<(chars.count - 1) {
                var c = chars; c.swapAt(i, i + 1)
                result.insert(String(c))
            }
        }
        // Replacements
        for i in 0..<chars.count {
            for letter in alphabet where letter != chars[i] {
                var c = chars; c[i] = letter
                result.insert(String(c))
            }
        }
        // Insertions
        for i in 0...chars.count {
            for letter in alphabet {
                var c = chars; c.insert(letter, at: i)
                result.insert(String(c))
            }
        }
        return result
    }
}
