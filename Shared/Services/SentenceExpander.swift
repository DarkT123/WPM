import Foundation

/// One successful expansion result. Keeps the segmentation alongside the
/// final sentence so corrections can be recorded as a (tokens, words)
/// alignment with no further parsing.
struct Expansion: Equatable {
    let tokens: [String]    // segmentation the decoder ran on
    let words: [String]     // final picked words (one per token)
    let sentence: String    // words.joined(separator: " ")
    let confidence: Double  // sentence-level confidence from BeamSearch
    let alternatives: [String]
}

/// Top-level orchestrator. Tries every chunker segmentation, runs beam
/// search on each, returns the highest-scoring expansion. Exact-pattern
/// hits short-circuit before any decoding.
final class SentenceExpander {

    let phrases: PhraseMemory
    let corrections: CorrectionMemory

    init(phrases: PhraseMemory, corrections: CorrectionMemory) {
        self.phrases = phrases
        self.corrections = corrections
    }

    /// Expand `shorthand` (no spaces, all letters). Returns `nil` if no
    /// segmentation is possible — the caller should leave the user's text
    /// alone in that case.
    func expand(_ shorthand: String) -> Expansion? {
        // Exact-pattern hit on the full shorthand bypasses decoding entirely.
        let normalized = shorthand.lowercased()
        if let cached = corrections.exactMatch(normalized) {
            let words = cached.split(separator: " ").map(String.init)
            if let tokens = matchingSegmentation(for: normalized, wordCount: words.count) {
                return Expansion(
                    tokens: tokens,
                    words: words,
                    sentence: cached,
                    confidence: 0.99,
                    alternatives: []
                )
            }
            // Word count drifted (user re-recorded with a different length).
            // Fall through to a fresh decode rather than emitting mismatched
            // (tokens, words).
        }

        let segs = ShorthandChunker.segmentations(normalized)
        if segs.isEmpty { return nil }

        var bestSeg: [String]?
        var bestResult: BeamResult?
        for seg in segs {
            let r = BeamSearch.decode(tokens: seg, phrases: phrases, corrections: corrections)
            if bestResult == nil || r.score > bestResult!.score {
                bestResult = r
                bestSeg = seg
            }
        }
        guard let result = bestResult, let seg = bestSeg, !result.best.isEmpty else { return nil }

        let words = result.words.map(\.selected)
        return Expansion(
            tokens: seg,
            words: words,
            sentence: result.best,
            confidence: result.confidence,
            alternatives: result.alternatives
        )
    }

    /// Pick a segmentation of `shorthand` whose token count matches the
    /// remembered correction's word count. We prefer the first matching
    /// segmentation; if none matches, return nil so the caller falls back
    /// to fresh decoding.
    private func matchingSegmentation(for shorthand: String, wordCount: Int) -> [String]? {
        for seg in ShorthandChunker.segmentations(shorthand) where seg.count == wordCount {
            return seg
        }
        return nil
    }

    /// Record an accepted/edited final sentence against the segmentation the
    /// user originally saw. `editedSentence` may differ from the offered
    /// expansion — that's the whole point.
    func recordCorrection(tokens: [String], editedSentence: String) {
        let words = editedSentence
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !words.isEmpty, words.count == tokens.count else { return }
        corrections.record(tokens: tokens, words: words)
    }

    // MARK: - Live (1-letter prefix) mode used by the macOS app

    struct LiveSuggestion: Equatable {
        let sentences: [String]   // up to `count`, best first
        let confidence: Double    // top sentence's confidence, 0..1
        /// Tokens that were fed to the beam — one per character of buffer
        /// for the 1-letter mode. The interceptor uses this length when
        /// computing how many backspaces to send before inserting.
        let tokens: [String]
    }

    /// Live decoder used by the macOS keystroke interceptor.
    ///
    /// `prefixLength`:
    ///   - `1`: every character of the buffer is its own prefix token.
    ///     Quick to type, very ambiguous.
    ///   - `2`: buffer is segmented into 2-letter chunks via the shorthand
    ///     chunker (which also handles `i`/`a` as 1-letter exceptions).
    ///     If the buffer's length isn't compatible with a clean 2-letter
    ///     segmentation, we automatically retry with the last typed char
    ///     dropped so suggestions don't disappear mid-chunk.
    ///
    /// Returns up to `count` candidates ranked by beam-search score.
    func liveSuggest(buffer: String, prefixLength: Int = 2, count: Int = 3) -> LiveSuggestion {
        let normalized = buffer.lowercased()
        guard normalized.count >= 2,
              normalized.allSatisfy({ $0.isLetter }) else {
            return LiveSuggestion(sentences: [], confidence: 0, tokens: [])
        }

        // Attempt 1: full buffer.
        if let result = decodeOnce(buffer: normalized, prefixLength: prefixLength, count: count) {
            return result
        }
        // Attempt 2 (2-letter only): drop the most recent char — handles
        // the "user is mid-chunk" case so the panel doesn't blink.
        if prefixLength == 2, normalized.count >= 3 {
            let truncated = String(normalized.dropLast())
            if let result = decodeOnce(buffer: truncated, prefixLength: prefixLength, count: count) {
                return result
            }
        }
        return LiveSuggestion(sentences: [], confidence: 0, tokens: [])
    }

    private func decodeOnce(buffer: String, prefixLength: Int, count: Int) -> LiveSuggestion? {
        let segmentations: [[String]]
        if prefixLength == 1 {
            segmentations = [buffer.map { String($0) }]
        } else {
            segmentations = ShorthandChunker.segmentations(buffer)
        }
        if segmentations.isEmpty { return nil }

        var best: BeamResult?
        var bestTokens: [String] = []
        for seg in segmentations {
            let r = BeamSearch.decode(
                tokens: seg,
                phrases: phrases,
                corrections: corrections,
                maxAlternatives: count + 4
            )
            if best == nil || r.score > best!.score {
                best = r
                bestTokens = seg
            }
        }
        guard let r = best, !r.best.isEmpty else { return nil }
        var out: [String] = [r.best]
        for alt in r.alternatives {
            if out.count >= count { break }
            if !out.contains(alt) { out.append(alt) }
        }
        return LiveSuggestion(sentences: out, confidence: r.confidence, tokens: bestTokens)
    }
}
