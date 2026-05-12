import Foundation
import SwiftUI
import UIKit

struct CorrectionLogEntry: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let shorthand: String
    let offered: String
    let corrected: String
    var didChange: Bool { offered != corrected }
}

/// The most-recent expansion the user has not yet committed by typing past
/// it. Range is in UTF-16 units, the same coordinate space UITextView uses.
private struct PendingCorrection {
    let tokens: [String]
    let shorthand: String
    let offered: String
    var range: NSRange
}

@MainActor
final class EditorViewModel: ObservableObject {

    @Published var text: String = ""
    @Published private(set) var correctionLog: [CorrectionLogEntry] = []
    @Published private(set) var lastExpansion: Expansion?

    let expander: SentenceExpander

    private var pending: PendingCorrection?
    /// Guard against re-entry when we programmatically replace text inside
    /// `textDidChange`.
    private var isApplyingExpansion = false

    init(expander: SentenceExpander) {
        self.expander = expander
    }

    // MARK: - Delegate hooks

    /// Called by the coordinator *before* a user edit applies. Adjusts the
    /// tracked range of the current pending correction so it still points
    /// at the same characters after the edit.
    func willReplaceText(in range: NSRange, with replacement: String) {
        guard var p = pending else { return }
        let replacementLength = (replacement as NSString).length
        let delta = replacementLength - range.length

        if NSMaxRange(range) <= p.range.location {
            // Edit lives entirely before the pending range — shift it.
            p.range.location += delta
        } else if range.location >= NSMaxRange(p.range) {
            // Edit lives entirely after — no adjustment needed.
        } else {
            // Edit overlaps the pending range. Absorb the length delta into
            // our tracked length, clamped to non-negative. If the edit
            // starts before the pending range but extends into it, also
            // shift the location forward to the new start of "our" text.
            let newLength = max(0, p.range.length + delta)
            if range.location < p.range.location {
                let shifted = p.range.location - range.location
                p.range.location = range.location + replacementLength - min(shifted, replacementLength)
            }
            p.range.length = newLength
            if p.range.length == 0 { pending = nil; return }
        }
        pending = p
    }

    /// Called by the coordinator after each text change has applied.
    func textDidChange(in textView: UITextView) {
        text = textView.text
        guard !isApplyingExpansion else { return }
        guard textView.text.hasSuffix(".") else { return }
        tryExpand(in: textView)
    }

    // MARK: - Expansion

    private func tryExpand(in textView: UITextView) {
        let documentText = textView.text ?? ""
        guard let match = ShorthandDetector.detect(in: documentText) else { return }
        guard let expansion = expander.expand(match.shorthand) else { return }

        // Finalize the previous pending correction first — read whatever is
        // currently at its tracked range, treat that as the user's final
        // version. Best-effort: if the range is malformed we just skip the
        // record.
        finalizePending(in: documentText)

        // Compute UTF-16 range of the shorthand+`.` in the document.
        let utf16Start = documentText.utf16Distance(from: documentText.startIndex, to: match.replaceRange.lowerBound)
        let utf16Length = documentText.utf16Distance(from: match.replaceRange.lowerBound, to: match.replaceRange.upperBound)
        let nsRange = NSRange(location: utf16Start, length: utf16Length)

        let replacement = expansion.sentence + "."
        let nsText = (textView.text ?? "") as NSString
        let newText = nsText.replacingCharacters(in: nsRange, with: replacement) as String

        // Apply text change reentrantly without re-triggering expansion.
        isApplyingExpansion = true
        defer { isApplyingExpansion = false }
        textView.text = newText
        text = newText

        let sentenceUTF16Length = (expansion.sentence as NSString).length
        pending = PendingCorrection(
            tokens: expansion.tokens,
            shorthand: match.shorthand,
            offered: expansion.sentence,
            range: NSRange(location: utf16Start, length: sentenceUTF16Length)
        )
        lastExpansion = expansion

        // Move the cursor to right after the inserted period.
        let cursor = utf16Start + (replacement as NSString).length
        textView.selectedRange = NSRange(location: cursor, length: 0)
    }

    private func finalizePending(in documentText: String) {
        guard let p = pending else { return }
        pending = nil
        let ns = documentText as NSString
        guard NSMaxRange(p.range) <= ns.length, p.range.length > 0 else { return }
        let edited = ns.substring(with: p.range)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if edited.isEmpty { return }
        expander.recordCorrection(tokens: p.tokens, editedSentence: edited)
        correctionLog.insert(
            CorrectionLogEntry(
                timestamp: Date(),
                shorthand: p.shorthand,
                offered: p.offered,
                corrected: edited
            ),
            at: 0
        )
    }

    /// Explicit save for users who edit the offered sentence without ever
    /// triggering another shorthand. Reads the current pending range and
    /// records the correction (if any).
    func commitPendingCorrection() {
        guard let p = pending else { return }
        let ns = text as NSString
        guard NSMaxRange(p.range) <= ns.length, p.range.length > 0 else { return }
        let edited = ns.substring(with: p.range)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if edited.isEmpty { return }
        expander.recordCorrection(tokens: p.tokens, editedSentence: edited)
        if edited != p.offered {
            correctionLog.insert(
                CorrectionLogEntry(
                    timestamp: Date(),
                    shorthand: p.shorthand,
                    offered: p.offered,
                    corrected: edited
                ),
                at: 0
            )
        }
        pending = nil
    }

    var hasPendingCorrection: Bool { pending != nil }
}

// MARK: - String <-> UTF-16 distance helper

private extension String {
    /// Distance in UTF-16 code units between two String.Index positions.
    /// UITextView's NSRange is in UTF-16 units; String.Index is in
    /// Character units. The two diverge for any non-BMP character.
    func utf16Distance(from a: String.Index, to b: String.Index) -> Int {
        let from = a.utf16Offset(in: self)
        let to = b.utf16Offset(in: self)
        return to - from
    }
}
