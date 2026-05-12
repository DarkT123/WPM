import Foundation
import AppKit
import ApplicationServices

@MainActor
final class AppState: ObservableObject {

    // MARK: - Published state

    @Published var isEnabled: Bool = false
    @Published var hasAccessibility: Bool = false
    @Published var bufferDisplay: String = ""
    @Published var suggestions: [String] = []          // currently-visible 3
    @Published var lastShorthand: String? = nil
    @Published var lastExpansion: String? = nil
    @Published var statusMessage: String = "Inactive — toggle to start listening."
    @Published var aiEnabled: Bool                      // true when MINIMAX_API_KEY is present
    @Published var aiInFlight: Bool = false             // for the UI's "thinking…" indicator
    @Published var styleNotes: String = ""              // appended to AI system prompt

    // MARK: - Dependencies

    private let interceptor: KeystrokeInterceptor
    private let panel: SuggestionPanel
    private let ai: MiniMaxClient?

    /// Last N (shorthand → final) pairs that the user accepted. Used as
    /// few-shot examples in subsequent AI calls.
    private var recentCorrections: [(shorthand: String, final: String)] = []

    /// Generation counter for the AI rerank — each new keystroke bumps it,
    /// and an in-flight rerank that finishes after the counter moved on is
    /// discarded.
    private var aiGeneration: UInt64 = 0
    private var debounceTask: Task<Void, Never>?

    init() {
        let phrases = PhraseMemory()
        let storeURL = AppState.defaultCorrectionStoreURL()
        let corrections = CorrectionMemory(storeURL: storeURL, phrases: phrases)
        let expander = SentenceExpander(phrases: phrases, corrections: corrections)
        self.interceptor = KeystrokeInterceptor(expander: expander)
        self.panel = SuggestionPanel()
        self.ai = MiniMaxClient.makeDefault()
        self.aiEnabled = (ai != nil)

        interceptor.didUpdate = { [weak self] buffer, suggestions in
            Task { @MainActor [weak self] in
                self?.handleUpdate(buffer: buffer, localSuggestions: suggestions)
            }
        }
        interceptor.didExpand = { [weak self] shorthand, sentence in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lastShorthand = shorthand
                self.lastExpansion = sentence
                self.recordCorrection(shorthand: shorthand, final: sentence)
            }
        }
    }

    private static func defaultCorrectionStoreURL() -> URL? {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = appSupport.appendingPathComponent("ShorthandMac", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("corrections.json")
    }

    // MARK: - Accessibility / toggle

    func refreshAccessibility() {
        hasAccessibility = AXIsProcessTrusted()
    }

    func toggle() {
        refreshAccessibility()
        if isEnabled {
            interceptor.stop()
            panel.hide()
            debounceTask?.cancel()
            isEnabled = false
            statusMessage = "Inactive — toggle to start listening."
            bufferDisplay = ""
            suggestions = []
            return
        }
        guard hasAccessibility else {
            requestAccessibility()
            statusMessage = "Accessibility permission required. Approve in System Settings, then toggle again."
            return
        }
        do {
            try interceptor.start()
            isEnabled = true
            statusMessage = aiEnabled
                ? "Active — local suggestions instant, MiniMax reranks after a brief pause."
                : "Active — local suggestions only (set MINIMAX_API_KEY in .env to enable AI)."
        } catch {
            statusMessage = "Failed to install event tap: \(error.localizedDescription)"
        }
    }

    func requestAccessibility() {
        let options: CFDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Update / panel placement

    private func handleUpdate(buffer: String, localSuggestions: [String]) {
        self.bufferDisplay = buffer
        aiGeneration &+= 1
        debounceTask?.cancel()

        if localSuggestions.isEmpty {
            self.suggestions = []
            panel.hide()
            aiInFlight = false
            return
        }

        // Show local suggestions immediately — never block on AI.
        self.suggestions = localSuggestions
        let topLeft = CaretLocator.panelTopLeftBelowCaret(panelHeight: 120)
        panel.show(at: topLeft, suggestions: localSuggestions) { [weak self] idx in
            Task { @MainActor in self?.pick(idx) }
        }

        // Kick off a debounced AI rerank when configured.
        guard let ai else { return }
        let myGeneration = aiGeneration
        let context = CaretLocator.contextAroundCaret()
        let tokens = buffer.map { String($0).lowercased() }
        let corrections = self.recentCorrections
        let notes = self.styleNotes
        aiInFlight = true

        debounceTask = Task { [weak self] in
            // 250ms pause-detection. If a new keystroke arrives, this Task
            // gets cancelled by `aiGeneration &+= 1` + `debounceTask?.cancel()`.
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }

            let req = AIRerankRequest(
                tokens: tokens,
                localCandidates: localSuggestions,
                contextBefore: context.before,
                contextAfter: context.after,
                recentCorrections: corrections,
                styleNotes: notes
            )
            let resp = await ai.rerank(req)

            await MainActor.run { [weak self] in
                guard let self else { return }
                guard self.aiGeneration == myGeneration else {
                    // A newer keystroke superseded this call; drop the result.
                    return
                }
                self.aiInFlight = false
                guard let resp, !resp.candidates.isEmpty else { return }
                self.suggestions = resp.candidates
                let topLeft = CaretLocator.panelTopLeftBelowCaret(panelHeight: 120)
                self.panel.show(at: topLeft, suggestions: resp.candidates) { [weak self] idx in
                    Task { @MainActor in self?.pick(idx) }
                }
            }
        }
    }

    // MARK: - Picks / learning

    /// Called by the suggestion panel when the user clicks row #idx.
    func pick(_ idx: Int) {
        let chosen = idx < suggestions.count ? suggestions[idx] : nil
        interceptor.applySuggestion(pickedIndex: idx, withTrailingPeriod: false)
        panel.hide()
        if let chosen, let buf = lastBufferSnapshot() {
            recordCorrection(shorthand: buf, final: chosen)
        }
    }

    private func lastBufferSnapshot() -> String? {
        bufferDisplay.isEmpty ? nil : bufferDisplay
    }

    private func recordCorrection(shorthand: String, final: String) {
        // Keep the most-recent 8 pairs, deduplicated by shorthand.
        recentCorrections.removeAll { $0.shorthand == shorthand }
        recentCorrections.insert((shorthand, final), at: 0)
        if recentCorrections.count > 8 {
            recentCorrections.removeLast()
        }
    }
}
