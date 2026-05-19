import Foundation

/// Local-first correction pipeline. Runs entirely in-process, in
/// microseconds, with no API call. The orchestration is:
///
///     normalize
///   → segment (Viterbi DP over LocalDictionary)
///   → token-level shorthand expansion (tmr → tomorrow, hw → homework, …)
///   → grammar polish (capitalization + contraction apostrophes)
///   → confidence scoring
///
/// AppState consults this BEFORE going to the LLM. When the local result
/// is high-confidence (every segmented token is in the dictionary), we
/// apply it immediately and feel like autocorrect. Otherwise we fall
/// through to the AI path, which knows how to deal with single-letter
/// shorthand and other ambiguous inputs.
enum LocalPipeline {

    struct Output {
        let expandedSentence: String
        let segments: [String]
        let unknownCount: Int
        let confidence: Double
        let latencyMs: Double
    }

    /// Token-level shorthand substitutions applied AFTER segmentation
    /// but BEFORE the grammar polisher. Single tokens that have multiple
    /// words in the expansion are emitted as space-separated phrases
    /// (the polisher joins with spaces anyway, so this just works).
    static let tokenExpansions: [String: String] = [
        "tmr":  "tomorrow",
        "tmrw": "tomorrow",
        "tmrrw":"tomorrow",
        "yest": "yesterday",
        "rn":   "right now",
        "hw":   "homework",
        "bc":   "because",
        "bcz":  "because",
        "cuz":  "because",
        "bday": "birthday",
        "idk":  "I don't know",
        "idc":  "I don't care",
        "imo":  "in my opinion",
        "imho": "in my honest opinion",
        "iirc": "if I recall correctly",
        "brb":  "be right back",
        "btw":  "by the way",
        "fyi":  "FYI",
        "lmk":  "let me know",
        "ttyl": "talk to you later",
        "tbh":  "to be honest",
        "smh":  "shaking my head",
        "lmao": "lmao",
        "omw":  "on my way",
        "nvm":  "never mind",
        "plz":  "please",
        "pls":  "please",
        "thx":  "thanks",
        "ty":   "thank you",
        "yw":   "you're welcome",
        "np":   "no problem",
        "ppl":  "people",
        "abt":  "about",
        "msg":  "message",
        "msgs": "messages",
        "prob": "probably",
        "def":  "definitely",
        "rly":  "really",
        "smth": "something",
        "nthg": "nothing",
        "frnd": "friend",
        "frnds":"friends",
        "schl": "school",
        "sch":  "school",
        "ofc":  "of course",
        "ily":  "I love you",
        "ur":   "your",
        "u":    "you",
        "w":    "with",
        "wo":   "without",
        "alot": "a lot",
    ]

    static func run(_ rawInput: String) -> Output {
        let start = Date()
        // 1. Normalize.
        let normalized = rawInput
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return Output(expandedSentence: "", segments: [], unknownCount: 0,
                          confidence: 0, latencyMs: 0)
        }

        // 2. Segment.
        let seg = WordSegmenter.segment(normalized)

        // 3. Token-level shorthand expansion. A single token may map to
        // a multi-word phrase; we split on space so the polisher sees
        // discrete words.
        let expanded: [String] = seg.segments.flatMap { token -> [String] in
            if let phrase = tokenExpansions[token] {
                return phrase.split(separator: " ").map(String.init)
            }
            return [token]
        }

        // 4. Grammar polish.
        let polished = GrammarPolisher.polish(expanded, originalInput: rawInput)

        // 5. Confidence — ratio of segmented tokens that are known
        // dictionary words, with two penalties:
        //   • short inputs (1-2 segments) get less confidence
        //   • bare single-letter segments (other than "i" / "a") signal
        //     that the segmenter ran out of real words to pick from —
        //     in that case we'd rather fall through to the LLM than
        //     emit nonsense
        let known = seg.segments.filter { LocalDictionary.contains($0) }.count
        let total = max(1, seg.segments.count)
        let knownRatio = Double(known) / Double(total)
        let lengthFactor: Double = total >= 3 ? 1.0 : (total == 2 ? 0.85 : 0.5)
        let bareSingleLetters = seg.segments.filter {
            $0.count == 1 && $0 != "i" && $0 != "a"
        }.count
        let singleLetterPenalty: Double = bareSingleLetters > 0 ? 0.5 : 1.0
        let confidence = knownRatio * lengthFactor * singleLetterPenalty

        let latencyMs = Date().timeIntervalSince(start) * 1000
        return Output(
            expandedSentence: polished,
            segments: seg.segments,
            unknownCount: seg.unknownCount,
            confidence: confidence,
            latencyMs: latencyMs
        )
    }
}
