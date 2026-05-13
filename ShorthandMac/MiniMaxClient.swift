import Foundation

struct ExpansionRequest {
    /// The compressed no-space token the user just typed (lowercased).
    let compressedInput: String
    /// Text immediately preceding the cursor in the host app (up to ~500 chars).
    let contextBefore: String
    /// Text immediately following the cursor.
    let contextAfter: String
    /// Frontmost app's localized name ("Notes", "Slack", "Messages") if known.
    let appName: String?
    /// Recent (compressed → final) corrections — used as few-shot examples.
    let recentCorrections: [(compressed: String, final: String)]
    /// User-supplied free-text style notes, appended to the system prompt.
    let styleNotes: String
}

/// One candidate from the AI plus its self-reported confidence. Used by
/// the local reranker to re-sort against typed-evidence / length / etc.
struct ExpansionCandidate: Equatable {
    let expanded: String
    let confidence: Double
}

struct ExpansionResponse: Equatable {
    /// False if the AI judges this is not actually shorthand (e.g. the
    /// user typed a real word like "hello" and pressed period).
    let shouldExpand: Bool
    /// Best-guess full sentence (best of `candidates`).
    let expanded: String
    /// Self-reported confidence of the best candidate, 0–1.
    let confidence: Double
    /// Up to 3 alternative sentences (strings only, for the panel).
    let alternatives: [String]
    /// Rich (sentence, confidence) tuples — best first. Used by the
    /// local reranker.
    let candidates: [ExpansionCandidate]
}

enum ExpansionError: Error, Equatable {
    case http(Int, String)
    case timeout
    case network(String)
    case parse(String)
    case noKey

    var displayMessage: String {
        switch self {
        case .http(let code, let msg):
            return "HTTP \(code): \(msg.prefix(120))"
        case .timeout:
            return "request timed out"
        case .network(let m):
            return "network: \(m.prefix(120))"
        case .parse(let m):
            return "couldn't parse response: \(m.prefix(120))"
        case .noKey:
            return "no API key configured"
        }
    }
}

/// Adapter for OpenAI-compatible chat-completions endpoints (MiniMax,
/// xAI, Groq, DeepSeek, OpenAI). Designed to fail open: a typed error
/// is returned so the caller can either inform the user or cancel the
/// expansion (re-inserting the user's original period).
final class MiniMaxClient {

    struct Config {
        let baseURL: URL
        let apiKey: String
        let model: String
        let timeout: TimeInterval

        static func fromEnv() -> Config? {
            guard let key = EnvLoader.value(for: "MINIMAX_API_KEY"),
                  !key.isEmpty else { return nil }
            let base = EnvLoader.value(for: "MINIMAX_API_BASE_URL") ?? "https://api.minimax.chat"
            guard let url = URL(string: base) else { return nil }
            let model = EnvLoader.value(for: "MINIMAX_MODEL") ?? "abab6.5-chat"
            let timeoutMs = Int(EnvLoader.value(for: "MINIMAX_TIMEOUT_MS") ?? "") ?? 30000
            return Config(baseURL: url, apiKey: key, model: model, timeout: TimeInterval(timeoutMs) / 1000)
        }
    }

    private let config: Config
    private let session: URLSession

    init(config: Config) {
        self.config = config
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = config.timeout
        cfg.timeoutIntervalForResource = config.timeout * 2
        cfg.urlCache = nil
        cfg.waitsForConnectivity = false
        self.session = URLSession(configuration: cfg)
    }

    static func makeDefault() -> MiniMaxClient? {
        guard let cfg = Config.fromEnv() else { return nil }
        return MiniMaxClient(config: cfg)
    }

    func expand(_ req: ExpansionRequest) async -> Result<ExpansionResponse, ExpansionError> {
        // Some providers expect the base URL to already include `/v1`
        // (xAI, MiniMax) — in which case we just append `chat/completions`.
        // Others expect just the host (no version path) — append the full
        // `/v1/chat/completions`. Pick based on whether the base path
        // already ends with `/v<digit>`.
        let basePath = config.baseURL.path
        let trimmed = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath
        let lastSegment = trimmed.split(separator: "/").last.map(String.init) ?? ""
        let alreadyVersioned = lastSegment.count >= 2
            && lastSegment.first == "v"
            && lastSegment.dropFirst().allSatisfy { $0.isNumber }
        let url = alreadyVersioned
            ? config.baseURL.appendingPathComponent("chat/completions")
            : config.baseURL.appendingPathComponent("v1/chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "authorization")

        let body: [String: Any] = [
            "model": config.model,
            "temperature": 0,
            "max_tokens": 3000,
            "messages": [
                ["role": "system", "content": Self.systemPrompt(styleNotes: req.styleNotes)],
                ["role": "user", "content": Self.userPrompt(req: req)],
            ],
        ]
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else {
            return .failure(.parse("encoding request body"))
        }
        request.httpBody = payload

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.network("no HTTP response"))
            }
            if http.statusCode != 200 {
                let msg = Self.extractServerMessage(data) ?? String(data: data, encoding: .utf8) ?? ""
                return .failure(.http(http.statusCode, msg))
            }
            if let parsed = Self.parse(data) {
                return .success(parsed)
            }
            return .failure(.parse("no expansion in response (model may have hit max_tokens during reasoning)"))
        } catch let err as URLError {
            if err.code == .timedOut { return .failure(.timeout) }
            if err.code == .cancelled { return .failure(.network("cancelled")) }
            return .failure(.network(err.localizedDescription))
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    private static func extractServerMessage(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let err = obj["error"] as? [String: Any], let m = err["message"] as? String { return m }
        if let m = obj["message"] as? String { return m }
        return nil
    }

    // MARK: - Prompt construction

    private static func systemPrompt(styleNotes: String) -> String {
        let base = """
        You are the expansion engine for Lazily, a hybrid shorthand writing app.

        The user types a compressed no-space version of a sentence and presses ".".
        Your job is to infer the most likely full sentence.

        THE INPUT IS FLEXIBLE — it may contain:
          • one-letter word hints
          • partial words (e.g. "sch" → "school", "tmrw" → "tomorrow")
          • full words without spaces
          • abbreviations (hw → homework, bc → because, rn → right now, u → you)
          • missing connector words (the, a, of, to, is, etc.)
          • any mixture of the above

        YOU MUST INFER
          • word boundaries
          • missing words
          • grammar
          • capitalization
          • the sentence that best fits surrounding context

        HARD RULES
        1. Return ONLY valid JSON in the exact format below. No markdown, no <think>, no commentary.
        2. Generate 3 candidate expansions, best first.
        3. Each sentence must be natural, grammatical English a fluent speaker would write.
        4. PREFER SIMPLE, LIKELY sentences over verbose / fancy ones.
        5. Treat the user's typed letters as STRONG EVIDENCE — every letter they typed must
           appear, in order, in your expanded sentence. You may insert connector words
           between them, but you may not skip or reorder their letters.
        6. If the user typed a clearly partial or full word ("sch", "home", "school"), preserve
           that meaning — don't replace it with a phonetically similar but different word.
        7. Use context_before and context_after to disambiguate.
        8. Use recent_corrections to match the user's style and prior word choices.
        9. Do NOT add a trailing period — the caller appends one.
        10. If the input is too ambiguous or actually reads as a normal English word the user
            probably typed deliberately, set "should_expand": false and leave best empty.
        11. Calibrate confidence honestly: 0.9+ when the answer is obvious; 0.5–0.7 when
            multiple readings are plausible; below 0.5 when you're guessing.

        OUTPUT FORMAT
        {
          "should_expand": true,
          "best": {
            "expanded_sentence": "I want to go to school",
            "confidence": 0.88,
            "reason": "Fits the compressed input and common phrasing."
          },
          "alternatives": [
            {"expanded_sentence": "I will go to school", "confidence": 0.72},
            {"expanded_sentence": "I went to school", "confidence": 0.61}
          ]
        }

        EXAMPLES

        Input: "tdrh"
        Context before: "I was walking through the park when "
        → {"should_expand": true, "best": {"expanded_sentence": "the dog ran home", "confidence": 0.9, "reason": "Most natural completion in this context."}, "alternatives": [{"expanded_sentence": "they did run home", "confidence": 0.55}, {"expanded_sentence": "that dog ran here", "confidence": 0.4}]}

        Input: "iwgotosch"
        Context before: "Yesterday my teacher asked where I was going. "
        → {"should_expand": true, "best": {"expanded_sentence": "I want to go to school", "confidence": 0.88, "reason": "‘sch’ → school; ‘iw’ → I want, with inserted ‘to’."}, "alternatives": [{"expanded_sentence": "I will go to school", "confidence": 0.72}, {"expanded_sentence": "I went to school", "confidence": 0.61}]}

        Input: "thedogranhome"
        Context before: ""
        → {"should_expand": true, "best": {"expanded_sentence": "The dog ran home", "confidence": 0.96, "reason": "Full words run together; just add spaces."}, "alternatives": [{"expanded_sentence": "Then the dog ran home", "confidence": 0.5}, {"expanded_sentence": "The dog ran home fast", "confidence": 0.4}]}

        Input: "tmrwihavetest"
        Context before: ""
        → {"should_expand": true, "best": {"expanded_sentence": "Tomorrow I have a test", "confidence": 0.9, "reason": "‘tmrw’ → tomorrow; insert ‘a’ before ‘test’."}, "alternatives": [{"expanded_sentence": "Tomorrow I have the test", "confidence": 0.65}, {"expanded_sentence": "Tomorrow I have tests", "confidence": 0.45}]}

        Input: "canyouhlpmewithhw"
        Context before: ""
        → {"should_expand": true, "best": {"expanded_sentence": "Can you help me with homework", "confidence": 0.9, "reason": "‘hlp’ → help; ‘hw’ → homework."}, "alternatives": [{"expanded_sentence": "Can you help me with my homework", "confidence": 0.75}, {"expanded_sentence": "Can you help me with the homework", "confidence": 0.6}]}

        Input: "hello"
        Context before: ""
        → {"should_expand": false, "best": {"expanded_sentence": "", "confidence": 0.0, "reason": "Already a normal English word."}, "alternatives": []}
        """
        let trimmed = styleNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return base }
        return base + "\n\nADDITIONAL STYLE PREFERENCES\n" + trimmed
    }

    private static func userPrompt(req: ExpansionRequest) -> String {
        var lines: [String] = []
        lines.append("Compressed shorthand token:")
        lines.append(req.compressedInput)
        lines.append("")
        if let app = req.appName, !app.isEmpty {
            lines.append("App where the user is typing: \(app)")
            lines.append("")
        }
        if !req.contextBefore.isEmpty {
            lines.append("Text before cursor:")
            lines.append(req.contextBefore)
            lines.append("")
        }
        if !req.contextAfter.isEmpty {
            lines.append("Text after cursor:")
            lines.append(req.contextAfter)
            lines.append("")
        }
        if let hints = AbbreviationHints.promptHints(for: req.compressedInput) {
            lines.append(hints)
            lines.append("")
        }
        if !req.recentCorrections.isEmpty {
            lines.append("Recent confirmed corrections from this user (style examples — prefer these word choices when applicable):")
            for c in req.recentCorrections.prefix(5) {
                lines.append("- \(c.compressed) → \(c.final)")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Response parsing

    private static func parse(_ data: Data) -> ExpansionResponse? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        var text: String?
        if let choices = obj["choices"] as? [[String: Any]],
           let first = choices.first,
           let message = first["message"] as? [String: Any],
           let content = message["content"] as? String {
            text = content
        } else if let reply = obj["reply"] as? String {
            text = reply
        }
        guard let text else { return nil }

        // Strip <think>...</think> blocks emitted by reasoning models.
        var cleaned = text
        while let open = cleaned.range(of: "<think>"),
              let close = cleaned.range(of: "</think>", range: open.upperBound..<cleaned.endIndex) {
            cleaned.removeSubrange(open.lowerBound..<close.upperBound)
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
            cleaned = cleaned.replacingOccurrences(of: "```", with: "")
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !cleaned.hasPrefix("{"),
           let firstBrace = cleaned.firstIndex(of: "{"),
           let lastBrace = cleaned.lastIndex(of: "}"),
           firstBrace < lastBrace {
            cleaned = String(cleaned[firstBrace...lastBrace])
        }

        guard let inner = cleaned.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: inner) as? [String: Any] else {
            return nil
        }

        let shouldExpand = (parsed["should_expand"] as? Bool) ?? true

        // Helper to read a confidence value tolerantly.
        func readConfidence(_ any: Any?) -> Double {
            if let n = any as? NSNumber { return n.doubleValue }
            if let s = any as? String, let d = Double(s) { return d }
            return 0.7
        }

        var candidates: [ExpansionCandidate] = []

        // Schema A (new, nested): {"best": {...}, "alternatives": [{...}]}
        if let best = parsed["best"] as? [String: Any] {
            let bestText = (best["expanded_sentence"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let bestConf = readConfidence(best["confidence"])
            if !bestText.isEmpty {
                candidates.append(ExpansionCandidate(expanded: bestText, confidence: bestConf))
            }
            if let alts = parsed["alternatives"] as? [[String: Any]] {
                for alt in alts {
                    let text = (alt["expanded_sentence"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let conf = readConfidence(alt["confidence"])
                    if !text.isEmpty {
                        candidates.append(ExpansionCandidate(expanded: text, confidence: conf))
                    }
                }
            }
        }

        // Schema B (old, flat): {"expanded_sentence": "...", "alternatives": ["..."]}
        if candidates.isEmpty {
            let expanded = (parsed["expanded_sentence"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let conf = readConfidence(parsed["confidence"])
            if !expanded.isEmpty {
                candidates.append(ExpansionCandidate(expanded: expanded, confidence: conf))
            }
            if let alts = parsed["alternatives"] as? [String] {
                let altConf = max(0, conf - 0.15)
                for a in alts {
                    let s = a.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !s.isEmpty {
                        candidates.append(ExpansionCandidate(expanded: s, confidence: altConf))
                    }
                }
            }
        }

        // Dedupe by normalized text, preserving order.
        var seen = Set<String>()
        candidates = candidates.filter {
            let key = $0.expanded.lowercased()
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }

        if shouldExpand && candidates.isEmpty { return nil }

        let best = candidates.first
        let alternatives = candidates.dropFirst().prefix(3).map { $0.expanded }

        return ExpansionResponse(
            shouldExpand: shouldExpand,
            expanded: best?.expanded ?? "",
            confidence: best?.confidence ?? 0,
            alternatives: Array(alternatives),
            candidates: candidates
        )
    }
}
