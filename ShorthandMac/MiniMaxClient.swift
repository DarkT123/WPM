import Foundation

struct AIRerankRequest {
    /// One-letter-prefix tokens the user has typed so far, lowercased.
    let tokens: [String]
    /// The current local-decoder top-3 (best first).
    let localCandidates: [String]
    /// Text immediately preceding the cursor in the host app (up to ~120 chars).
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
            let timeoutMs = Int(EnvLoader.value(for: "MINIMAX_TIMEOUT_MS") ?? "") ?? 500
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
                ["role": "system", "content": Self.systemPrompt(styleNotes: req.styleNotes)],
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

    private static func systemPrompt(styleNotes: String) -> String {
        let base = """
        You expand shorthand into full English sentences.

        Each shorthand token is the first letter of one intended word. The output sentence has exactly the same number of words as there are tokens, and each output word starts with the corresponding letter (case-insensitive). Use the surrounding text context to choose the right words.

        Apply natural English capitalization (sentence start, proper nouns) and punctuation. Do NOT add a trailing period — the caller appends one if needed.

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
