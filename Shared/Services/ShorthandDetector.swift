import Foundation

/// Decides whether the run of characters immediately before a `.` looks like
/// shorthand worth trying to expand. The rule (per the product spec):
///
///   1. Must end with `.`
///   2. The run from the most recent boundary (start, whitespace, or
///      punctuation other than `.`) to the `.` must contain *only* letters.
///   3. Run length must be ≥ `minLength` so trivial words like "ok." aren't
///      caught. Default 4 — the shortest sensible shorthand is two 2-letter
///      chunks.
///
/// When detected, `match.shorthand` is the letter run and `match.range` is
/// the substring range inside the input (including the period) that should
/// be replaced when the expansion is accepted.
enum ShorthandDetector {

    struct Match: Equatable {
        let shorthand: String
        /// Range covering the letters PLUS the trailing period in the source.
        /// Replace this whole range with the expanded sentence + a period.
        let replaceRange: Range<String.Index>
    }

    static let defaultMinLength = 4

    /// Returns a Match iff `text` ends with `.` and the run before that `.`
    /// is a contiguous letter sequence of at least `minLength`.
    /// `text` is the document text up to (and including) the trigger period.
    static func detect(in text: String, minLength: Int = defaultMinLength) -> Match? {
        guard let last = text.last, last == "." else { return nil }
        let periodIndex = text.index(before: text.endIndex)

        // Walk backward from just before the period, collecting letters.
        var runStart = periodIndex
        var i = periodIndex
        while i > text.startIndex {
            let prev = text.index(before: i)
            let c = text[prev]
            if c.isLetter {
                runStart = prev
                i = prev
            } else {
                break
            }
        }

        // No letters before the period → not shorthand.
        if runStart == periodIndex { return nil }
        let shorthand = String(text[runStart..<periodIndex])
        if shorthand.count < minLength { return nil }
        // Don't transform if the run is itself a real word — keeps normal
        // sentences like "I am tired." passing through.
        if PrefixDictionary.isCommonWord(shorthand) { return nil }

        // If the character just before the run is a letter, that means we
        // hit text-start. Otherwise we hit a space or other non-letter,
        // which is the boundary we wanted. Either way `runStart` is correct.
        return Match(
            shorthand: shorthand,
            replaceRange: runStart..<text.index(after: periodIndex)
        )
    }
}
