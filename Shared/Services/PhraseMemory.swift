import Foundation

/// Bigram + trigram store with curated baseline phrases plus phrases learned
/// from user corrections. Mirrors Edge's `phraseMemory.ts`, simplified to a
/// single domain — the iOS app's first cut is general English.
final class PhraseMemory {

    private struct Table {
        var bigrams: [String: Int]
        var trigrams: [String: Int]
    }

    private static let starterBigrams: [String: Int] = [
        "i want": 18, "want to": 25, "to make": 20, "to be": 15,
        "to go": 12, "to do": 14, "to see": 10, "to take": 8,
        "make a": 14, "make sure": 6, "make it": 7,
        "a good": 12, "a great": 10, "a new": 9,
        "we are": 12, "are going": 14, "going to": 18, "to the": 18,
        "the place": 4, "the store": 5, "the school": 5,
        "it was": 14, "was a": 10,
        "of the": 22, "in the": 22, "on the": 18, "for the": 14,
        "and the": 16, "with the": 12, "from the": 12, "at the": 16,
        "i am": 12, "you are": 10, "he is": 8, "she is": 8,
        "they are": 9, "we will": 7, "will be": 9, "have been": 9,
        "has been": 8, "had been": 6, "i think": 8, "i know": 7,
        "do you": 8, "can you": 6, "thank you": 8, "see you": 7,
        "this is": 9, "that is": 9, "there is": 8, "there are": 8,
        "is a": 12, "is the": 12, "is not": 8, "do not": 7,
        "the same": 9, "the other": 8, "the only": 7, "the first": 9,
        "the last": 9, "the next": 8, "right now": 6, "every day": 8,
        "all the": 10, "look at": 6,
        "i went": 5, "i was": 12, "i had": 10, "i need": 8,
        "the dog": 6, "dog ran": 4, "ran home": 3, "to home": 0,
        "the cat": 6, "the quick": 5, "quick brown": 8, "brown fox": 8,
        "prediction market": 18, "market research": 16, "research app": 10,
    ]

    private static let starterTrigrams: [String: Int] = [
        "i want to": 24, "i went to": 12, "i had to": 10, "i need to": 12,
        "want to make": 14, "want to be": 10, "want to go": 12, "want to see": 8,
        "to make a": 16, "make a prediction": 8, "make a decision": 4,
        "a prediction market": 14, "prediction market research": 14,
        "market research app": 12, "to be a": 8,
        "is going to": 10, "we are going": 10, "are going to": 14,
        "going to the": 12, "going to be": 10, "going to make": 6,
        "thank you for": 6, "what do you": 7, "what are you": 6,
        "the dog ran": 6, "dog ran home": 4,
    ]

    private var starter: Table
    private var learned: Table

    init() {
        starter = Table(
            bigrams: PhraseMemory.starterBigrams,
            trigrams: PhraseMemory.starterTrigrams
        )
        learned = Table(bigrams: [:], trigrams: [:])
    }

    func bigramScore(_ prev: String, _ current: String) -> Double {
        guard !prev.isEmpty, !current.isEmpty else { return 0 }
        let key = "\(prev.lowercased()) \(current.lowercased())"
        return lookup(starter: starter.bigrams, learned: learned.bigrams, key: key)
    }

    func trigramScore(_ prev2: String, _ prev1: String, _ current: String) -> Double {
        guard !prev2.isEmpty, !prev1.isEmpty, !current.isEmpty else { return 0 }
        let key = "\(prev2.lowercased()) \(prev1.lowercased()) \(current.lowercased())"
        return lookup(starter: starter.trigrams, learned: learned.trigrams, key: key)
    }

    private func lookup(starter s: [String: Int], learned l: [String: Int], key: String) -> Double {
        let starterCount = Double(s[key] ?? 0)
        let learnedCount = Double(l[key] ?? 0)
        // Learned phrases outweigh curated once confirmed.
        return starterCount + learnedCount * 3.0
    }

    func learn(_ words: [String]) {
        let ws = words.map { $0.lowercased() }
        guard ws.count >= 2 else { return }
        for i in 0..<(ws.count - 1) {
            let key = "\(ws[i]) \(ws[i + 1])"
            learned.bigrams[key, default: 0] += 1
        }
        if ws.count >= 3 {
            for i in 0..<(ws.count - 2) {
                let key = "\(ws[i]) \(ws[i + 1]) \(ws[i + 2])"
                learned.trigrams[key, default: 0] += 1
            }
        }
    }

    // MARK: - Persistence helpers

    struct Snapshot: Codable {
        let bigrams: [String: Int]
        let trigrams: [String: Int]
    }

    func snapshot() -> Snapshot {
        Snapshot(bigrams: learned.bigrams, trigrams: learned.trigrams)
    }

    func restore(_ snap: Snapshot) {
        learned.bigrams = snap.bigrams
        learned.trigrams = snap.trigrams
    }
}
