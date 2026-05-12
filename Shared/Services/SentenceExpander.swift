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

    /// 1-letter-prefix decoder. Each character of `buffer` is treated as a
    /// single prefix token. Used by the macOS keystroke interceptor to
    /// produce live suggestions as the user types — no period trigger, no
    /// chunker DP, no `i`/`a` exception logic needed because every char is
    /// already its own token. Returns up to `count` candidates (best first).
    func liveSuggest(buffer: String, count: Int = 3) -> LiveSuggestion {
        let normalized = buffer.lowercased()
        guard normalized.count >= 2,
              normalized.allSatisfy({ $0.isLetter }) else {
            return LiveSuggestion(sentences: [], confidence: 0, tokens: [])
        }
        let tokens = normalized.map { String($0) }
        let result = BeamSearch.decode(
            tokens: tokens,
            phrases: phrases,
            corrections: corrections,
            maxAlternatives: count + 4
        )
        if result.best.isEmpty {
            return LiveSuggestion(sentences: [], confidence: 0, tokens: tokens)
        }
        var out: [String] = [result.best]
        for alt in result.alternatives {
            if out.count >= count { break }
            if !out.contains(alt) { out.append(alt) }
        }
        return LiveSuggestion(sentences: out, confidence: result.confidence, tokens: tokens)
    }
}
