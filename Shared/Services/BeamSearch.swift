import Foundation

/// Per-word output from the decoder. Mirrors Edge's `WordCandidate`.
struct DecodedWord: Equatable {
    let token: String          // the prefix (or literal) the decoder consumed
    let selected: String       // chosen word
    let candidates: [String]   // top alternatives, best first
    let confidence: Double     // 0..1
}

/// Final result from `BeamSearch.decode`.
struct BeamResult: Equatable {
    let best: String                  // joined sentence
    let words: [DecodedWord]
    let alternatives: [String]
    let confidence: Double
    /// Cumulative log-likelihood of the best beam. Used by the orchestrator
    /// to compare segmentations against each other.
    let score: Double
}

enum BeamSearch {

    private static let obscurityThreshold = 500
    private static let obscurityPenalty = 1.0

    /// Inputs are already-parsed prefix tokens. Single-letter literals
    /// (`a`, `i`) come through as their own one-element bucket.
    static func decode(
        tokens: [String],
        phrases: PhraseMemory,
        corrections: CorrectionMemory,
        beamWidth: Int = 20,
        maxAlternatives: Int = 8
    ) -> BeamResult {
        guard !tokens.isEmpty else {
            return BeamResult(best: "", words: [], alternatives: [], confidence: 0, score: 0)
        }

        // Per-position candidate lists. `i`/`a` short-circuit as their literal
        // word (the chunker decides whether to emit "i" vs "ih" — by the time
        // we're here, "i"/"a" means the user typed that as a 1-letter chunk).
        let candidates: [[String]] = tokens.map { t in
            let lower = t.lowercased()
            if lower == "i" || lower == "a" { return [lower] }
            return PrefixDictionary.candidates(forPrefix: lower)
        }

        struct Beam {
            var words: [String]
            var score: Double
        }

        var beams: [Beam] = [Beam(words: [], score: 0)]

        for i in 0..<tokens.count {
            let token = tokens[i].lowercased()
            // Right-context preview: top-of-bucket candidate for position i+1
            // if available (refined automatically on the next iteration).
            let next = i + 1 < tokens.count ? (candidates[i + 1].first ?? "") : ""

            var expanded: [Beam] = []
            for beam in beams {
                let prev1 = beam.words.last ?? ""
                let prev2 = beam.words.count >= 2 ? beam.words[beam.words.count - 2] : ""

                for word in candidates[i] {
                    let inc = stepScore(
                        prev2: prev2, prev1: prev1,
                        word: word, token: token, next: next,
                        phrases: phrases, corrections: corrections
                    )
                    expanded.append(Beam(words: beam.words + [word], score: beam.score + inc))
                }
            }

            expanded.sort { $0.score > $1.score }
            beams = Array(expanded.prefix(beamWidth))
        }

        let top = Array(beams.prefix(maxAlternatives))
        guard let bestBeam = top.first else {
            return BeamResult(best: "", words: [], alternatives: [], confidence: 0, score: 0)
        }
        let second = top.count > 1 ? top[1].score : nil
        let conf = sentenceConfidence(topScore: bestBeam.score, secondScore: second)

        var seen = Set<String>([bestBeam.words.joined(separator: " ")])
        var alternatives: [String] = []
        for b in top.dropFirst() {
            let s = b.words.joined(separator: " ")
            if seen.contains(s) || s.isEmpty { continue }
            seen.insert(s); alternatives.append(s)
        }

        let words = computePerWordCandidates(
            picked: bestBeam.words,
            tokens: tokens,
            allCandidates: candidates,
            phrases: phrases,
            corrections: corrections
        )

        return BeamResult(
            best: bestBeam.words.joined(separator: " "),
            words: words,
            alternatives: alternatives,
            confidence: conf,
            score: bestBeam.score
        )
    }

    // MARK: - Scoring

    private static func stepScore(
        prev2: String, prev1: String,
        word: String, token: String, next: String,
        phrases: PhraseMemory, corrections: CorrectionMemory
    ) -> Double {
        let freq = max(1, PrefixDictionary.frequency(of: word))
        var s = log(Double(freq + 1))

        s += phrases.bigramScore(prev1, word)
        s += phrases.trigramScore(prev2, prev1, word) * 1.4

        if !next.isEmpty {
            s += phrases.bigramScore(word, next) * 0.8
        }

        let boost = corrections.wordBoost(prefix: token, word: word)
        if boost > 0 { s += log(1.0 + Double(boost)) * 2.5 }

        // The strongest local signal — same (prev, prefix → word) confirmed
        // before should dominate weaker n-gram contributions.
        let succ = corrections.prefixSuccessorBoost(prev: prev1, prefix: token, word: word)
        if succ > 0 { s += log(1.0 + Double(succ)) * 4.0 }

        if freq < obscurityThreshold { s -= obscurityPenalty }
        return s
    }

    private static func computePerWordCandidates(
        picked: [String],
        tokens: [String],
        allCandidates: [[String]],
        phrases: PhraseMemory,
        corrections: CorrectionMemory
    ) -> [DecodedWord] {
        var out: [DecodedWord] = []
        for i in 0..<tokens.count {
            let cs = allCandidates[i]
            let prev1 = i > 0 ? picked[i - 1] : ""
            let prev2 = i > 1 ? picked[i - 2] : ""
            let next = i + 1 < picked.count ? picked[i + 1] : ""

            let scored = cs.map { c in
                (
                    c,
                    stepScore(
                        prev2: prev2, prev1: prev1,
                        word: c, token: tokens[i], next: next,
                        phrases: phrases, corrections: corrections
                    )
                )
            }.sorted { $0.1 > $1.1 }

            let best = scored.first?.1 ?? 0
            let second = scored.count > 1 ? scored[1].1 : nil
            let conf = wordConfidence(best: best, second: second, options: scored.count)

            out.append(DecodedWord(
                token: tokens[i],
                selected: picked[i],
                candidates: scored.map(\.0),
                confidence: conf
            ))
        }
        return out
    }

    // MARK: - Confidence

    private static func logistic(_ x: Double, _ k: Double) -> Double {
        1.0 / (1.0 + exp(-k * x))
    }

    private static let softMax = 0.99

    private static func sentenceConfidence(topScore: Double, secondScore: Double?) -> Double {
        guard let s = secondScore, s.isFinite else { return 0.95 }
        let gap = topScore - s
        return max(0, min(softMax, logistic(gap, 1.5)))
    }

    private static func wordConfidence(best: Double, second: Double?, options: Int) -> Double {
        if options <= 1 { return 1 }
        guard let s = second, s.isFinite else { return 0.95 }
        return max(0, min(softMax, logistic(best - s, 2)))
    }
}
