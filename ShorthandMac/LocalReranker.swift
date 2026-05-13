import Foundation

/// Re-scores AI candidates against typed-evidence / length / lexical
/// heuristics before AppState picks the best one.
///
/// The AI's self-reported confidence is a useful starting point, but
/// models are over-confident in failure cases — a low-effort completion
/// can come back with 0.85 even when it has dropped letters or ignored
/// an obvious abbreviation. The local rerank catches those.
///
/// Scoring is multiplicative against the AI confidence so we never
/// promote a candidate above the AI's own prior, only demote bad ones.
enum LocalReranker {

    /// Re-score and re-sort `candidates`. Returns a new ExpansionResponse
    /// with the reranked order and updated confidences.
    static func rerank(_ resp: ExpansionResponse,
                       compressedInput: String,
                       recentCorrections: [(compressed: String, final: String)]) -> ExpansionResponse {
        guard resp.shouldExpand, !resp.candidates.isEmpty else { return resp }

        let dictionary = NorvigSet.shared
        let scored: [ExpansionCandidate] = resp.candidates.map { cand in
            let s = score(cand,
                          compressedInput: compressedInput,
                          recentCorrections: recentCorrections,
                          dictionary: dictionary)
            // Multiplicative damping by the local score in [0.3, 1.05].
            let newConf = min(0.99, cand.confidence * s)
            return ExpansionCandidate(expanded: cand.expanded, confidence: newConf)
        }
        let sorted = scored.sorted { $0.confidence > $1.confidence }
        let best = sorted.first
        let alts = sorted.dropFirst().prefix(3).map { $0.expanded }

        return ExpansionResponse(
            shouldExpand: resp.shouldExpand,
            expanded: best?.expanded ?? resp.expanded,
            confidence: best?.confidence ?? resp.confidence,
            alternatives: Array(alts),
            candidates: sorted
        )
    }

    /// Returns a multiplier in roughly [0.3, 1.05]. 1.0 = no change.
    private static func score(_ cand: ExpansionCandidate,
                              compressedInput: String,
                              recentCorrections: [(compressed: String, final: String)],
                              dictionary: NorvigSet) -> Double {
        var s = 1.0
        let lowerOut = cand.expanded.lowercased()
        let words = lowerOut.split(whereSeparator: { !$0.isLetter && $0 != "'" })
            .map { String($0) }

        // 1. Letter coverage: every letter of compressedInput must appear
        // in order in the candidate. This is also enforced by the prompt
        // but models occasionally drop letters.
        let coverage = letterCoverageRatio(compressedInput, lowerOut)
        if coverage < 1.0 {
            // Missing letters is a serious problem.
            s *= max(0.3, 1.0 - (1.0 - coverage) * 2.0)
        }

        // 2. Length sanity: expansions much longer than 3× compressed
        // length are usually verbose hallucinations.
        let expectedMaxWords = max(3, compressedInput.count)
        if words.count > expectedMaxWords + 4 {
            s *= 0.7
        } else if words.count > expectedMaxWords + 2 {
            s *= 0.9
        }
        if words.isEmpty { s *= 0.5 }

        // 3. Rare-word penalty: if most words aren't in the top-10k
        // common-English list, the sentence is probably awkward or wrong.
        if !words.isEmpty {
            let common = words.filter { dictionary.contains($0) }.count
            let ratio = Double(common) / Double(words.count)
            if ratio < 0.5 { s *= 0.75 }
            else if ratio < 0.7 { s *= 0.9 }
        }

        // 4. Repeated-word penalty: "I I want to to school" etc.
        if hasAdjacentRepeats(words) { s *= 0.7 }

        // 5. Abbreviation-anchor adherence: if the user typed "tmrw",
        // the candidate should contain "tomorrow". If it doesn't, demote.
        for (range, meaning) in AbbreviationHints.anchors(in: compressedInput) {
            let meaningLower = meaning.lowercased()
            if !lowerOut.contains(meaningLower) {
                // Lighter penalty (0.85) since the AI may legitimately
                // override the hint in context.
                s *= 0.85
                _ = range
            }
        }

        // 6. Recent-correction match bonus: if any past correction
        // produced exactly this sentence for a similar compressed input,
        // boost slightly.
        for c in recentCorrections {
            if c.final.lowercased() == lowerOut && c.compressed == compressedInput {
                s *= 1.05
                break
            }
        }

        return s
    }

    /// Fraction of compressed input letters that appear in `output` in
    /// order. 1.0 = full coverage.
    private static func letterCoverageRatio(_ compressed: String, _ output: String) -> Double {
        let needle = Array(compressed.lowercased())
        guard !needle.isEmpty else { return 1.0 }
        var i = 0
        for ch in output where i < needle.count && ch == needle[i] {
            i += 1
        }
        return Double(i) / Double(needle.count)
    }

    private static func hasAdjacentRepeats(_ words: [String]) -> Bool {
        guard words.count >= 2 else { return false }
        for j in 1..<words.count where words[j] == words[j - 1] {
            return true
        }
        return false
    }
}

/// Lazy Set wrapper around NorvigTop10k for O(1) word membership.
final class NorvigSet {
    static let shared = NorvigSet()
    private let words: Set<String>
    private init() {
        self.words = Set(NorvigTop10k.entries.lazy.map { $0.0 })
    }
    func contains(_ word: String) -> Bool {
        words.contains(word.lowercased())
    }
}
