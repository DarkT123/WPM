import Foundation

/// Takes the segmenter's lowercase token list and turns it into a
/// polished sentence — capitalization, contraction apostrophes, and a
/// few simple grammar fixes. No LLM call.
///
/// Examples:
///   ["im", "going", "to", "the", "store", "tomorrow"]
///     → "I'm going to the store tomorrow"
///   ["dont", "tell", "me", "what", "to", "do"]
///     → "Don't tell me what to do"
///   ["i", "love", "you"] → "I love you"
enum GrammarPolisher {

    /// Maps contractions-without-apostrophe back to their proper form.
    /// Order matters only for documentation — lookup is by exact match.
    static let contractionMap: [String: String] = [
        "im": "I'm",
        "ive": "I've",
        "ill": "I'll",
        "id": "I'd",
        "dont": "don't",
        "doesnt": "doesn't",
        "didnt": "didn't",
        "wont": "won't",
        "wouldnt": "wouldn't",
        "cant": "can't",
        "couldnt": "couldn't",
        "shouldnt": "shouldn't",
        "isnt": "isn't",
        "arent": "aren't",
        "wasnt": "wasn't",
        "werent": "weren't",
        "hasnt": "hasn't",
        "havent": "haven't",
        "hadnt": "hadn't",
        "mustnt": "mustn't",
        "youre": "you're",
        "youve": "you've",
        "youll": "you'll",
        "youd": "you'd",
        "theyre": "they're",
        "theyve": "they've",
        "theyll": "they'll",
        "theyd": "they'd",
        "weve": "we've",
        "wed": "we'd",
        "hes": "he's",
        "shes": "she's",
        "thats": "that's",
        "whats": "what's",
        "wheres": "where's",
        "whens": "when's",
        "hows": "how's",
        "theres": "there's",
        "heres": "here's",
        "whos": "who's",
        "lets": "let's",
        "aint": "ain't",
        "yall": "y'all",
    ]

    /// Polish the tokens. `original` is the raw compressed input — used
    /// only to detect whether the user typed a known proper noun
    /// substring (none yet, future expansion).
    static func polish(_ tokens: [String], originalInput: String) -> String {
        guard !tokens.isEmpty else { return "" }
        var out: [String] = []
        for (idx, t) in tokens.enumerated() {
            let lower = t.lowercased()
            var word = contractionMap[lower] ?? lower
            // Stand-alone "i" → "I"
            if word == "i" { word = "I" }
            // Capitalize the first word.
            if idx == 0 {
                word = capitalizeFirst(word)
            }
            out.append(word)
        }
        return out.joined(separator: " ")
    }

    /// Capitalize the first letter while preserving the rest (so "I'm"
    /// stays "I'm" instead of becoming "I'M").
    private static func capitalizeFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }
}
