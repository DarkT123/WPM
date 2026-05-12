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
    /// `1` = type one letter per word (very ambiguous, faster typing).
    /// `2` = type two letters per word (~5× less ambiguous, default).
    @Published var prefixLength: Int = 2 {
        didSet {
            interceptor.prefixLength = prefixLength
        }
    }

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
        self.interceptor.prefixLength = 2
        self.panel = SuggestionPanel()
        self.ai = MiniMaxClient.makeDefault()
        self.aiEnabled = (ai != nil)
        // When AI is configured, the panel + period auto-apply both wait
        // for AI to produce candidates. Local results never reach the UI.
        self.interceptor.aiOnly = (ai != nil)

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
            interceptor.overrideSuggestions = []
            panel.hide()
            aiInFlight = false
            return
        }

        // When AI is NOT configured, local is all we have — show it.
        // When AI IS configured, hide the panel and wait for AI; we don't
        // want local-dilution junk in front of the user.
        if ai == nil {
            self.suggestions = localSuggestions
            interceptor.overrideSuggestions = []
            let topLeft = CaretLocator.panelTopLeftBelowCaret(panelHeight: 120)
            panel.show(at: topLeft, suggestions: localSuggestions) { [weak self] idx in
                Task { @MainActor in self?.pick(idx) }
            }
            return
        }
        // AI is configured — keep the panel empty until AI rerank arrives.
        self.suggestions = []
        interceptor.overrideSuggestions = []
        panel.hide()

        // Kick off a debounced AI rerank.
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
                self.interceptor.overrideSuggestions = resp.candidates
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
