import Foundation

/// Minimal `.env` reader. Looks in three places, first-hit-wins:
///   1. `SHORTHAND_ENV_FILE` environment variable (override for testing)
///   2. `<repo-root>/.env` — the file the user creates next to project.yml
///   3. `~/.shorthand-mac.env` — alternative location away from any repo
///
/// Parses lines of the form `KEY=value`. Ignores comments (`#`) and blank
/// lines. Values may optionally be wrapped in double quotes.
enum EnvLoader {

    private static var cache: [String: String]?

    static func value(for key: String) -> String? {
        if let cache { return cache[key] }
        let loaded = loadAll()
        cache = loaded
        return loaded[key]
    }

    static func reload() {
        cache = nil
    }

    private static func loadAll() -> [String: String] {
        var out: [String: String] = [:]
        for url in candidatePaths() {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for raw in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.isEmpty || line.hasPrefix("#") { continue }
                guard let eq = line.firstIndex(of: "=") else { continue }
                let key = line[..<eq].trimmingCharacters(in: .whitespaces)
                var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                    value = String(value.dropFirst().dropLast())
                }
                if !key.isEmpty, out[key] == nil {
                    out[key] = value
                }
            }
        }
        return out
    }

    private static func candidatePaths() -> [URL] {
        var paths: [URL] = []
        if let override = ProcessInfo.processInfo.environment["SHORTHAND_ENV_FILE"], !override.isEmpty {
            paths.append(URL(fileURLWithPath: override))
        }
        // Workspace root .env — same file used by Edge.
        paths.append(URL(fileURLWithPath: "/Users/andyzhao/Translating keyboard/.env"))
        // Per-user fallback.
        let home = FileManager.default.homeDirectoryForCurrentUser
        paths.append(home.appendingPathComponent(".shorthand-mac.env"))
        return paths
    }
}
