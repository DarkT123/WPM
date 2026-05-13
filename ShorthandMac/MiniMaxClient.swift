import Foundation

struct ExpansionRequest {
    /// The compressed no-space token the user just typed (lowercased).
    /// Could be one letter per word ("tdrh"), partial words ("iwgotosch"),
    /// or full words mashed together ("thedogranhome").
    let compressedInput: String
    /// Text immediately preceding the cursor in the host app (up to ~500 chars).
    let contextBefore: String
    /// Text immediately following the cursor.
    let contextAfter: String
    /// Recent (compressed → final) corrections — used as few-shot examples.
    let recentCorrections: [(compressed: String, final: String)]
    /// User-supplied free-text style notes, appended to the system prompt.
    let styleNotes: String
}

struct ExpansionResponse: Equatable {
    /// False if the AI judges this is not actually shorthand (e.g. the
    /// user typed a real word like "hello" and pressed period). Caller
    /// should leave the typed text alone in that case.
    let shouldExpand: Bool
    /// Best-guess full sentence. Empty when shouldExpand is false.
    let expanded: String
    /// Up to ~3 alternative sentences for the user to swap to.
    let alternatives: [String]
    /// Self-reported confidence, 0–1. Used by the UI to decide whether to
    /// auto-hide the alternatives panel quickly or leave it lingering.
    let confidence: Double
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
        You are a shorthand expander for an English typing assistant.

        The user types a compressed, no-space "shorthand token" and then presses ".".
        Your job is to infer the full sentence they intended, including word boundaries,
        missing connector words (articles, prepositions, etc.), capitalization, and grammar.

        THE SHORTHAND IS FLEXIBLE — the user may use:
          • the first letter of each word ("tdrh" → "the dog ran home")
          • the first two letters of each word ("thdorah" → "the dog ran home")
          • partial words mixed together ("iwgotosch" → "I want to go to school")
          • full words run together with no spaces ("thedogranhome" → "the dog ran home")
          • any mixture of the above

        HARD RULES
        1. Coverage: every letter the user typed must appear, in order, somewhere in your
           expanded sentence. You may insert extra words (articles, prepositions, helpers)
           between the user's letters, but you may not skip or reorder their letters.
        2. Word boundaries: pick word boundaries so the result reads as a fluent, natural
           English sentence that continues the surrounding context. The number of words is
           NOT fixed; choose whatever count makes the sentence read naturally.
        3. Capitalization & grammar: apply natural English capitalization (sentence start,
           "I", proper nouns) and grammar (subject-verb agreement, tense matching the
           surrounding context). Do NOT add a trailing period — the caller appends one.
        4. Safety: if the compressed input is so short or ambiguous that any guess would be
           a stretch, OR if it actually reads as a normal English word that the user probably
           typed deliberately, set "should_expand": false and leave "expanded_sentence" empty.

        OUTPUT FORMAT
        Return ONLY this JSON, no markdown, no <think> blocks, no commentary:
        {
          "should_expand": true,
          "expanded_sentence": "I want to go to school",
          "confidence": 0.88,
          "alternatives": ["I will go to school", "I went to school"]
        }

        EXAMPLES

        Tokens: "tdrh"
        Context before: "I was walking through the park when "
        →
        {"should_expand": true, "expanded_sentence": "the dog ran home", "confidence": 0.9, "alternatives": ["they did rush here", "the doors remained here"]}

        Tokens: "iwgotosch"
        Context before: "Yesterday my teacher asked where I was going. "
        →
        {"should_expand": true, "expanded_sentence": "I want to go to school", "confidence": 0.88, "alternatives": ["I will go to school", "I went to school"]}

        Tokens: "thedogranhome"
        Context before: ""
        →
        {"should_expand": true, "expanded_sentence": "The dog ran home", "confidence": 0.95, "alternatives": ["The dog ran home fast", "Then the dog ran home"]}

        Tokens: "hello"
        Context before: ""
        →
        {"should_expand": false, "expanded_sentence": "", "confidence": 0.0, "alternatives": []}
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
        if !req.recentCorrections.isEmpty {
            lines.append("Recent confirmed corrections from this user (style examples):")
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
        let expanded = (parsed["expanded_sentence"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let confidence: Double = {
            if let n = parsed["confidence"] as? NSNumber { return n.doubleValue }
            if let s = parsed["confidence"] as? String, let d = Double(s) { return d }
            return 0.7
        }()
        let alternatives = ((parsed["alternatives"] as? [String]) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if shouldExpand && expanded.isEmpty { return nil }

        return ExpansionResponse(
            shouldExpand: shouldExpand,
            expanded: expanded,
            alternatives: Array(alternatives.prefix(3)),
            confidence: confidence
        )
    }
}
