import Foundation

/// Mirror of the container app's `AppServices`, instantiated per-extension
/// process. Both targets share the same `Shared/Services` types, but each
/// builds its own object graph. Persistent stores (correction memory)
/// live in the App Group container so corrections recorded in either
/// process are visible to the other.
@MainActor
final class ExtensionServices {
    static let shared = ExtensionServices()

    let phrases: PhraseMemory
    let corrections: CorrectionMemory
    let expander: SentenceExpander

    private init() {
        let p = PhraseMemory()
        let c = CorrectionMemory(phrases: p)
        self.phrases = p
        self.corrections = c
        self.expander = SentenceExpander(phrases: p, corrections: c)
    }
}
