import Foundation
import UIKit

/// Drives the shorthand keyboard. Owns shift state, the in-flight pending
/// correction, and the bridge to `UITextDocumentProxy` / the host's
/// `advanceToNextInputMode()`. Lifetime is the input view controller's.
@MainActor
final class KeyboardModel: ObservableObject {

    @Published private(set) var isShifted: Bool = false
    @Published private(set) var isCapsLock: Bool = false
    /// Most recent expansion. Surfaced in the preview bar so the user has
    /// quick feedback that the substitution happened.
    @Published private(set) var lastExpansionSummary: String?

    private let proxy: UITextDocumentProxy
    private let expander: SentenceExpander

    /// Trampoline to `UIInputViewController.advanceToNextInputMode()`. Set
    /// by the controller — the model is otherwise UIKit-agnostic.
    var advanceToNextInputMode: (() -> Void)?

    // MARK: - Pending correction (per-process; not persisted)

    private struct Pending {
        let tokens: [String]
        let offered: String
        let shorthand: String
    }

    private var pending: Pending?

    init(proxy: UITextDocumentProxy, expander: SentenceExpander) {
        self.proxy = proxy
        self.expander = expander
    }

    // MARK: - Letter keys

    func letterTapped(_ lowercase: String) {
        let shouldUppercase = isShifted || isCapsLock
        let character = shouldUppercase ? lowercase.uppercased() : lowercase
        proxy.insertText(character)
        if isShifted, !isCapsLock { isShifted = false }
    }

    func shiftTapped() {
        if isCapsLock {
            isCapsLock = false
            isShifted = false
        } else if isShifted {
            isCapsLock = true
        } else {
            isShifted = true
        }
    }

    // MARK: - Word/sentence boundary keys

    func spaceTapped() {
        proxy.insertText(" ")
    }

    func returnTapped() {
        proxy.insertText("\n")
    }

    func deleteTapped() {
        proxy.deleteBackward()
        // Conservative: deletions inside the offered sentence make our
        // pending range unreliable. We can still finalize on the next `.`
        // by re-reading the document context, so just keep `pending` as-is.
    }

    /// The shorthand trigger. Intercepts BEFORE inserting the period — when
    /// the run preceding the cursor is detectable shorthand we substitute
    /// the expansion in place; otherwise the period passes through.
    func periodTapped() {
        let beforeContext = proxy.documentContextBeforeInput ?? ""
        let virtualContext = beforeContext + "."
        if let match = ShorthandDetector.detect(in: virtualContext),
           let expansion = expander.expand(match.shorthand) {

            // Finalize any pending correction by reading the user's current
            // version of the previously-offered sentence from the live
            // context, before we change the document state.
            finalizePending(against: beforeContext)

            // Drop the shorthand letters the user just typed — the period
            // hasn't been inserted yet, so we don't delete that.
            let shorthandLen = match.shorthand.count
            for _ in 0..<shorthandLen { proxy.deleteBackward() }

            let replacement = expansion.sentence + "."
            proxy.insertText(replacement)

            pending = Pending(
                tokens: expansion.tokens,
                offered: expansion.sentence,
                shorthand: match.shorthand
            )
            lastExpansionSummary = "\(match.shorthand) → \(expansion.sentence)"
            return
        }
        // No shorthand match — just type the period normally.
        proxy.insertText(".")
    }

    func globeTapped() {
        advanceToNextInputMode?()
    }

    // MARK: - Pending correction finalization

    /// Extract the most-recent completed sentence in `context` and, if we
    /// have a pending expansion, record what the user kept (which may
    /// equal the offered sentence — that still teaches phrase memory).
    private func finalizePending(against context: String) {
        guard let p = pending else { return }
        pending = nil
        guard let sentence = mostRecentCompletedSentence(in: context),
              !sentence.isEmpty else { return }
        expander.recordCorrection(tokens: p.tokens, editedSentence: sentence)
        if sentence != p.offered {
            lastExpansionSummary = "Learned: \(p.shorthand) → \(sentence)"
        }
    }

    /// Walks back from the end of `context`, skipping the in-flight
    /// shorthand letters, then any whitespace, then reads the run of
    /// characters up to the next earlier `.` (or text start). Returns nil
    /// if there's no recognizable previous sentence.
    private func mostRecentCompletedSentence(in context: String) -> String? {
        var i = context.endIndex
        while i > context.startIndex,
              context[context.index(before: i)].isLetter {
            i = context.index(before: i)
        }
        while i > context.startIndex,
              context[context.index(before: i)].isWhitespace {
            i = context.index(before: i)
        }
        guard i > context.startIndex,
              context[context.index(before: i)] == "." else {
            return nil
        }
        let prevPeriodEnd = context.index(before: i)
        var j = prevPeriodEnd
        while j > context.startIndex {
            let prev = context.index(before: j)
            if context[prev] == "." {
                return context[j..<prevPeriodEnd]
                    .trimmingCharacters(in: .whitespaces)
            }
            j = context.index(before: j)
        }
        return context[context.startIndex..<prevPeriodEnd]
            .trimmingCharacters(in: .whitespaces)
    }
}
