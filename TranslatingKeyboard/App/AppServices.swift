import Foundation

/// Single shared dependency container for the container app. Created on
/// first access; lifetime is the app process. Tests bypass this by
/// constructing the underlying services directly.
@MainActor
final class AppServices {
    static let shared = AppServices()

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
