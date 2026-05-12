import Foundation

/// Splits a continuous shorthand string into prefix tokens. Each token is
/// either a 2-letter slice of the input, or the literal single character
/// `i` or `a` at that position (the only single-letter English words the
/// spec recognises as exceptions).
///
/// Multiple valid segmentations exist whenever an `i` or `a` straddles a
/// chunk boundary — the orchestrator runs the decoder on all of them and
/// keeps the best-scoring result.
enum ShorthandChunker {

    /// Up to `max` valid segmentations of `shorthand`. Returns `[]` if no
    /// valid segmentation exists (e.g. odd length without a 1-letter slot
    /// for `i`/`a`).
    static func segmentations(_ shorthand: String, max: Int = 8) -> [[String]] {
        let chars = Array(shorthand.lowercased())
        let n = chars.count
        if n == 0 { return [] }
        // Guard against non-letters slipping in — the detector should have
        // filtered already, but defence in depth.
        for c in chars {
            if !c.isLetter { return [] }
        }

        // dp[i] = all segmentations consuming the first i characters.
        var dp: [[[String]]] = Array(repeating: [], count: n + 1)
        dp[0] = [[]]

        for i in 1...n {
            var pool: [[String]] = []

            let c = chars[i - 1]
            if c == "i" || c == "a" {
                for seg in dp[i - 1] {
                    pool.append(seg + [String(c)])
                    if pool.count >= max { break }
                }
            }

            if pool.count < max, i >= 2 {
                let chunk = String(chars[(i - 2)..<i])
                for seg in dp[i - 2] {
                    pool.append(seg + [chunk])
                    if pool.count >= max { break }
                }
            }

            dp[i] = Array(pool.prefix(max))
        }

        return dp[n]
    }
}
