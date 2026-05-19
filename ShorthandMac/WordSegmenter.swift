import Foundation

/// Splits a no-space input ("imgoingtothestoretmr") into its most-likely
/// word sequence (["im", "going", "to", "the", "store", "tmr"]) using a
/// memoized Viterbi-style dynamic-programming search over word
/// log-probabilities from LocalDictionary.
///
/// Algorithm:
///   - For every prefix `head` of the input up to 20 chars, score
///     `logProb(head) + bestSegmentation(tail).score`.
///   - Take the argmax; memoize the (tail → best) decisions.
///   - 80-char input → ~6 400 prefix evaluations — sub-millisecond.
///
/// This is Norvig's classic word-segmentation trick (Beautiful Data
/// chapter 14), adapted to Swift.
enum WordSegmenter {

    struct Result {
        let segments: [String]
        /// Sum of log probabilities. Less-negative = better.
        let score: Double
        /// Count of segments not in LocalDictionary.
        let unknownCount: Int
    }

    /// Cap on how long a single segmented word can be. 20 covers
    /// English's longest natural words ("internationalization" = 20).
    static let maxWordLen = 20

    static func segment(_ text: String) -> Result {
        let lower = text.lowercased()
        guard !lower.isEmpty else {
            return Result(segments: [], score: 0, unknownCount: 0)
        }
        var memo: [Substring: (segments: [String], score: Double)] = [:]
        memo.reserveCapacity(lower.count)

        let segments = solve(Substring(lower), memo: &memo)
        let unknowns = segments.segments.filter { !LocalDictionary.contains($0) }.count
        return Result(segments: segments.segments, score: segments.score, unknownCount: unknowns)
    }

    private static func solve(_ s: Substring,
                              memo: inout [Substring: (segments: [String], score: Double)])
        -> (segments: [String], score: Double) {
        if s.isEmpty { return ([], 0) }
        if let cached = memo[s] { return cached }

        var best: (segments: [String], score: Double) = (
            [String(s)],
            LocalDictionary.logProb(String(s)) - 5  // discourage falling back to "whole string as one unknown word"
        )

        let upper = min(s.count, maxWordLen)
        for i in 1...upper {
            let mid = s.index(s.startIndex, offsetBy: i)
            let head = s[s.startIndex..<mid]
            let tail = s[mid..<s.endIndex]
            let headLogP = LocalDictionary.logProb(String(head))
            let tailResult = solve(tail, memo: &memo)
            let total = headLogP + tailResult.score
            if total > best.score {
                best = ([String(head)] + tailResult.segments, total)
            }
        }

        memo[s] = best
        return best
    }
}
