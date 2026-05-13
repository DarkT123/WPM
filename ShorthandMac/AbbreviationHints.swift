import Foundation

/// A small curated table of texting / student shorthand whose meaning is
/// strongly conventional. When one of these substrings appears inside a
/// compressed input, Lazily passes a "this almost certainly means X"
/// hint to the LLM so the expansion respects user intent.
///
/// The AI can still override these in context (e.g. "u-shape" → "u"
/// stays "u"), so this is anchoring, not forcing.
enum AbbreviationHints {

    /// Ordered longest-first — when we scan a compressed input for
    /// hints, longer entries should match before shorter ones (so "tmrw"
    /// beats "tm").
    static let table: [(token: String, meaning: String)] = [
        // High-value common ones — preserve order, longest first.
        ("tmrw", "tomorrow"),
        ("tmr",  "tomorrow"),
        ("yest", "yesterday"),
        ("rn",   "right now"),
        ("hw",   "homework"),
        ("bc",   "because"),
        ("bcz",  "because"),
        ("cuz",  "because"),
        ("bday", "birthday"),
        ("idk",  "I don't know"),
        ("idc",  "I don't care"),
        ("imo",  "in my opinion"),
        ("imho", "in my honest opinion"),
        ("iirc", "if I recall correctly"),
        ("brb",  "be right back"),
        ("btw",  "by the way"),
        ("fyi",  "for your information"),
        ("lmk",  "let me know"),
        ("ttyl", "talk to you later"),
        ("tbh",  "to be honest"),
        ("smh",  "shaking my head"),
        ("lol",  "lol"),
        ("omw",  "on my way"),
        ("nvm",  "never mind"),
        ("plz",  "please"),
        ("pls",  "please"),
        ("thx",  "thanks"),
        ("ty",   "thank you"),
        ("yw",   "you're welcome"),
        ("np",   "no problem"),
        ("ppl",  "people"),
        ("abt",  "about"),
        ("msg",  "message"),
        ("msgs", "messages"),
        ("prob", "probably"),
        ("def",  "definitely"),
        ("rly",  "really"),
        ("kinda","kind of"),
        ("sorta","sort of"),
        ("gotta","got to"),
        ("wanna","want to"),
        ("gonna","going to"),
        ("smth", "something"),
        ("smthg","something"),
        ("smthn","something"),
        ("nthg", "nothing"),
        ("evry", "every"),
        ("frnd", "friend"),
        ("frnds","friends"),
        ("schl", "school"),
        ("sch",  "school"),
        ("ofc",  "of course"),
        ("af",   "as fuck"),
        ("ily",  "I love you"),
        ("ur",   "your"),
        ("u",    "you"),
        ("w",    "with"),
        ("wo",   "without"),
        ("w/",   "with"),
        ("w/o",  "without"),
        ("rly",  "really"),
        ("alot", "a lot"),
    ]

    /// Greedy left-to-right scan: returns the longest non-overlapping
    /// matches of table entries inside `compressed`. Each anchor is
    /// `(range_in_compressed, suggested_meaning)`. Result is rendered
    /// as a list of hint lines for the LLM prompt.
    static func anchors(in compressed: String) -> [(range: Range<String.Index>, meaning: String)] {
        let lower = compressed.lowercased()
        var anchors: [(Range<String.Index>, String)] = []
        var i = lower.startIndex
        while i < lower.endIndex {
            var matched: (Range<String.Index>, String)? = nil
            for (token, meaning) in table {
                let endOffset = i.utf16Offset(in: lower) + token.count
                guard endOffset <= lower.utf16.count else { continue }
                let end = lower.index(lower.startIndex, offsetBy: token.count, limitedBy: lower.endIndex)
                    .flatMap { _ in lower.index(i, offsetBy: token.count, limitedBy: lower.endIndex) }
                guard let end else { continue }
                if lower[i..<end] == token {
                    matched = (i..<end, meaning)
                    break
                }
            }
            if let (range, meaning) = matched {
                anchors.append((range, meaning))
                i = range.upperBound
            } else {
                i = lower.index(after: i)
            }
        }
        return anchors
    }

    /// Pretty-print the anchors as a hint block for the AI user prompt.
    /// Returns nil if nothing matched (caller shouldn't bother adding
    /// the section to the prompt).
    static func promptHints(for compressed: String) -> String? {
        let found = anchors(in: compressed)
        guard !found.isEmpty else { return nil }
        var lines = ["Likely substring meanings (use as strong evidence — override only if context clearly says otherwise):"]
        for (range, meaning) in found {
            let token = compressed[range]
            lines.append("- “\(token)” → \(meaning)")
        }
        return lines.joined(separator: "\n")
    }
}
