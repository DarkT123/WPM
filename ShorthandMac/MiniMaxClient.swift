import Foundation

struct AIRerankRequest {
    /// Prefix tokens the user has typed so far, lowercased. With
    /// `prefixLength == 1` each token is one letter; with `prefixLength == 2`
    /// each token is 1–2 letters (`i`/`a` may be 1 letter; the rest 2).
    let tokens: [String]
    /// `1` or `2` — describes the encoding scheme so the AI can interpret
    /// the tokens correctly.
    let prefixLength: Int
    /// The current local-decoder top-3 (best first).
    let localCandidates: [String]
    /// Text immediately preceding the cursor in the host app (up to ~500 chars).
    let contextBefore: String
    /// Text immediately following the cursor (rarely useful but cheap to include).
    let contextAfter: String
    /// Recent (shorthand → final) corrections — used as few-shot examples.
    let recentCorrections: [(shorthand: String, final: String)]
    /// User-supplied free-text style notes, appended to the system prompt.
    let styleNotes: String
}

struct AIRerankResponse: Equatable {
    let candidates: [String]   // best first, up to 3
}

/// MiniMax adapter. Speaks the same OpenAI-compatible chat-completions
/// endpoint as the Edge backend version. Designed to fail open: any error
/// returns nil so the caller keeps showing local suggestions.
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
            let timeoutMs = Int(EnvLoader.value(for: "MINIMAX_TIMEOUT_MS") ?? "") ?? 1500
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

    /// Build a config from the user's `.env` file. Returns nil if no key
    /// is present (caller treats this as "AI disabled, local only").
    static func makeDefault() -> MiniMaxClient? {
        guard let cfg = Config.fromEnv() else { return nil }
        return MiniMaxClient(config: cfg)
    }

    /// Hits the chat-completions endpoint. Returns nil on timeout, network
    /// error, non-2xx, or unparseable response.
    func rerank(_ req: AIRerankRequest) async -> AIRerankResponse? {
        let url = config.baseURL.appendingPathComponent("/v1/chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "authorization")

        let body: [String: Any] = [
            "model": config.model,
            "temperature": 0.2,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": Self.systemPrompt(styleNotes: req.styleNotes, prefixLength: req.prefixLength)],
                ["role": "user", "content": Self.userPrompt(req: req)],
            ],
        ]
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else {
            return nil
        }
        request.httpBody = payload

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            return Self.parse(data)
        } catch {
            return nil
        }
    }

    // MARK: - Prompt construction

    private static func systemPrompt(styleNotes: String, prefixLength: Int) -> String {
        let encodingRule: String
        if prefixLength == 1 {
            encodingRule = "Each shorthand token is the FIRST LETTER of one intended word. The output has exactly the same number of words as tokens, and each output word starts with the corresponding letter (case-insensitive)."
        } else {
            encodingRule = "Each shorthand token is the FIRST ONE OR TWO LETTERS of one intended word. Single-letter tokens are limited to 'i' or 'a' (English single-letter words); every other token is a two-letter prefix. The output has exactly the same number of words as tokens, and each output word starts with the corresponding prefix (case-insensitive)."
        }
        let base = """
        You expand a user's shorthand into full, grammatically correct English sentences.

        \(encodingRule)

        Use the surrounding text context to disambiguate. Apply natural English capitalization (sentence start, proper nouns) and punctuation INSIDE the sentence, but do NOT add a trailing period — the caller appends one if needed.

        Produce only sentences a fluent English speaker would actually write. Discard candidates that are grammatical noise.

        Return ONLY JSON of the form:
        {"candidates": ["best sentence", "second", "third"]}
        Order from most likely to least likely. Always return exactly 3 candidates.
        """
        let trimmed = styleNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return base }
        return base + "\n\nAdditional style preferences from the user:\n" + trimmed
    }

    private static func userPrompt(req: AIRerankRequest) -> String {
        var lines: [String] = []
        lines.append("Tokens (one letter per intended word):")
        lines.append(req.tokens.joined(separator: " "))
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
        if !req.localCandidates.isEmpty {
            lines.append("Local decoder's current guesses (improve or replace):")
            for (i, c) in req.localCandidates.prefix(3).enumerated() {
                lines.append("\(i + 1). \(c)")
            }
            lines.append("")
        }
        if !req.recentCorrections.isEmpty {
            lines.append("Recent confirmed corrections from this user (style examples):")
            for c in req.recentCorrections.prefix(5) {
                lines.append("- \(c.shorthand) → \(c.final)")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Response parsing

    private static func parse(_ data: Data) -> AIRerankResponse? {
        // OpenAI-style: choices[0].message.content is a JSON string.
        // MiniMax may also surface `reply` directly.
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

        // Some models wrap the JSON in markdown fences — strip them.
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
            cleaned = cleaned.replacingOccurrences(of: "```", with: "")
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let inner = cleaned.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: inner) as? [String: Any],
              let candidates = parsed["candidates"] as? [String] else {
            return nil
        }
        let trimmed = candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if trimmed.isEmpty { return nil }
        return AIRerankResponse(candidates: Array(trimmed.prefix(3)))
    }
}
