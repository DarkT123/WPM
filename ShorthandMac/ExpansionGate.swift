import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Pre-AI sanity checks. The interceptor has already buffered a 2–80
/// letter no-space token and the user pressed ".". Before we send that
/// token to the LLM (cost + latency + chance of a false-positive expand),
/// run cheap local heuristics to reject the cases where expanding would
/// almost certainly be wrong:
///
///   • the focused app is a place where shorthand is dangerous (Terminal,
///     IDE, password manager)
///   • the user is typing into a secure (password) field
///   • the surrounding text shows we're inside a URL / file path / email /
///     code identifier
///   • the buffered token *is* a normal English word the user almost
///     certainly typed deliberately ("hello.", "thanks.")
///
/// If the gate blocks, AppState restores the swallowed period and the
/// user's text is left untouched.
enum ExpansionGate {

    enum Decision: Equatable {
        case proceed
        case skip(reason: String)
    }

    /// Apps where intercepting keystrokes is more likely to break the
    /// user than help them. Matched by bundle identifier.
    static let excludedBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "io.alacritty",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "co.zeit.hyper",
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.visualstudio.code.oss",
        "com.todesktop.230313mzl4w4u92",  // Cursor
        "com.exafunction.windsurf",
        "com.apple.dt.Xcode",
        "com.sublimetext.4",
        "com.sublimetext.3",
        "com.jetbrains.intellij",
        "com.jetbrains.intellij.ce",
        "com.jetbrains.pycharm",
        "com.jetbrains.pycharm.ce",
        "com.jetbrains.WebStorm",
        "com.jetbrains.RubyMine",
        "com.jetbrains.AppCode",
        "com.jetbrains.CLion",
        "com.jetbrains.goland",
        "com.jetbrains.rider",
        "com.jetbrains.datagrip",
        "com.jetbrains.PhpStorm",
        "com.1password.1password",
        "com.1password.1password7",
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword4",
        "com.bitwarden.desktop",
        "com.lastpass.LastPass",
        "com.dashlane.Dashlane",
        "com.keepassxc.keepassxc",
    ]

    /// Built once on first use — Norvig top-10k words as a Set for O(1)
    /// lookup. Plus a small extra list of "obvious" short words that
    /// might fall just outside the top 10k.
    static let commonEnglishWords: Set<String> = {
        var s = Set<String>(NorvigTop10k.entries.lazy.map { $0.0 })
        // Defensive extras in case ranking varies.
        let extras = [
            // Conversational interjections that don't always show up in the
            // top-10k written-corpus list but are obviously real words.
            "ok", "okay", "hi", "hey", "yo", "yep", "yup", "nope",
            "lol", "lmao", "wtf", "tbh", "imo", "afk", "btw", "fyi",
            "wait", "huh", "oof", "ugh", "meh", "ah", "oh", "uh",
            // Technical-context single words a user might type into Notes
            // / chat that nobody wants expanded.
            "readme", "todo", "fixme", "src", "lib", "config", "init",
            "main", "true", "false", "null", "nil", "var", "let", "func",
        ]
        for w in extras { s.insert(w) }
        return s
    }()

    /// The main decision. AppState calls this with the buffered token,
    /// the text before/after the cursor (already pulled from AX), and
    /// the current focused-app bundle ID.
    static func check(compressed: String,
                      contextBefore: String,
                      contextAfter: String,
                      focusedAppBundleID: String?,
                      aggressiveMode: Bool,
                      excludedAppOverrides: Set<String> = []) -> Decision {

        // 1. Secure input (e.g. typing in a password field).
        if IsSecureEventInputEnabled() {
            return .skip(reason: "secure input is enabled")
        }

        // 2. Focused app is excluded by default.
        if let app = focusedAppBundleID,
           excludedBundleIDs.contains(app) || excludedAppOverrides.contains(app) {
            return .skip(reason: "app \(app) is in the excluded list")
        }

        // 3. Surrounding text looks like URL / path / email / code.
        if let reason = surroundingLooksTechnical(before: contextBefore, after: contextAfter) {
            return .skip(reason: reason)
        }

        // 4. Buffer is a normal English word — unless aggressive mode.
        if !aggressiveMode {
            let lower = compressed.lowercased()
            if commonEnglishWords.contains(lower) {
                return .skip(reason: "‘\(compressed)’ is a normal English word")
            }
            // Very short tokens almost always read as real words or typos.
            if compressed.count <= 3 {
                return .skip(reason: "token too short (\(compressed.count) chars) — likely a normal word")
            }
        }

        return .proceed
    }

    // MARK: - Helpers

    /// Returns a non-nil reason string if the text immediately around the
    /// cursor looks like a URL, file path, email, or code identifier.
    private static func surroundingLooksTechnical(before: String, after: String) -> String? {
        // Look at a small window — typing context only matters if it's
        // immediately adjacent. Beyond ~30 chars it's usually unrelated.
        let recentBefore = String(before.suffix(40))
        let recentAfter = String(after.prefix(20))

        // URLs / schemes anywhere recent.
        if recentBefore.contains("://") || recentAfter.contains("://") {
            return "cursor is inside a URL"
        }

        // Need to look at the contiguous run of non-space characters
        // ending at the cursor — that's the "word" the user is typing
        // into. If that contains a slash, '@', or a dot followed by
        // letters, it's almost certainly a path / email / domain / filename.
        let wordAtCursor: String = {
            var t = ""
            for ch in recentBefore.reversed() {
                if ch == " " || ch == "\t" || ch == "\n" { break }
                t.append(ch)
            }
            return String(t.reversed())
        }()

        if wordAtCursor.contains("/") {
            return "cursor is inside a file path"
        }
        if wordAtCursor.contains("@") {
            return "cursor is inside an email / handle"
        }
        if wordAtCursor.contains(":") {
            return "cursor is inside a code-like token (‘:’ in current word)"
        }
        if wordAtCursor.contains("_") || wordAtCursor.contains("-") {
            return "cursor is inside an identifier"
        }
        // A previous "." somewhere in the current word suggests we're
        // inside something like "README.md" — the user just typed letters
        // after the dot. Note: the interceptor's word boundary is
        // whitespace, not '.', so this is possible.
        if wordAtCursor.dropLast().contains(".") {
            return "cursor is inside a dotted token (e.g. filename, domain)"
        }

        return nil
    }
}
