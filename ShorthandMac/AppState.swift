import Foundation
import AppKit
import ApplicationServices

@MainActor
final class AppState: ObservableObject {

    // MARK: - Published state

    @Published var isEnabled: Bool = false
    @Published var hasAccessibility: Bool = false
    @Published var bufferDisplay: String = ""
    @Published var statusMessage: String = "Inactive — toggle to start listening."
    @Published var aiEnabled: Bool
    @Published var aiInFlight: Bool = false
    @Published var aiLastError: String? = nil
    @Published var styleNotes: String = ""
    @Published var lastCompressed: String? = nil
    @Published var lastExpansion: String? = nil
    @Published var lastAlternatives: [String] = []

    // MARK: - Dependencies

    private let interceptor: KeystrokeInterceptor
    private let panel: SuggestionPanel
    private let ai: MiniMaxClient?

    /// Recent (compressed → final) corrections, used as few-shot examples.
    private var recentCorrections: [(compressed: String, final: String)] = []

    /// State tracked between an expansion landing and the user either
    /// accepting it (timeout), swapping, or undoing.
    private struct LiveExpansion {
        let compressed: String
        var picked: String     // currently-inserted sentence (without ".")
        let alternatives: [String]
    }
    private var liveExpansion: LiveExpansion?
    /// Generation counter so an old AI response that arrives after a
    /// newer trigger gets discarded.
    private var generation: UInt64 = 0
    /// Hide-the-panel timer after a successful expansion.
    private var hideTask: Task<Void, Never>?

    init() {
        self.interceptor = KeystrokeInterceptor()
        self.panel = SuggestionPanel()
        self.ai = MiniMaxClient.makeDefault()
        self.aiEnabled = (ai != nil)

        interceptor.didBufferChange = { [weak self] buf in
            Task { @MainActor [weak self] in self?.bufferDisplay = buf }
        }
        interceptor.didRequestExpansion = { [weak self] compressed in
            Task { @MainActor [weak self] in self?.handleExpansionRequest(compressed) }
        }
        interceptor.didExpand = { [weak self] compressed, expanded in
            Task { @MainActor [weak self] in
                self?.lastCompressed = compressed
                self?.lastExpansion = expanded
                self?.recordCorrection(compressed: compressed, final: expanded)
            }
        }
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
            hideTask?.cancel()
            isEnabled = false
            statusMessage = "Inactive — toggle to start listening."
            bufferDisplay = ""
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
                ? "Active — type a compressed sentence, then press . to expand."
                : "Active — but AI is not configured. Add MINIMAX_API_KEY to .env and relaunch."
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

    // MARK: - Expansion flow

    private func handleExpansionRequest(_ compressed: String) {
        FileHandle.standardError.write(Data("[appstate] expansion request: '\(compressed)'\n".utf8))
        generation &+= 1
        let myGen = generation
        hideTask?.cancel()

        guard let ai else {
            // No AI configured — re-insert the period the interceptor swallowed.
            aiLastError = "no API key configured — set MINIMAX_API_KEY in .env"
            interceptor.cancelExpansion()
            return
        }

        let context = CaretLocator.contextAroundCaret(maxChars: 500)
        let topLeft = CaretLocator.panelTopLeftBelowCaret(panelHeight: 140)
        aiInFlight = true
        panel.showExpanding(at: topLeft, compressed: compressed)

        let req = ExpansionRequest(
            compressedInput: compressed,
            contextBefore: context.before,
            contextAfter: context.after,
            recentCorrections: recentCorrections,
            styleNotes: styleNotes
        )

        Task { [weak self] in
            let result = await ai.expand(req)
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard self.generation == myGen else { return }
                self.aiInFlight = false
                switch result {
                case .success(let resp):
                    FileHandle.standardError.write(Data("[appstate] AI ok: should=\(resp.shouldExpand) expanded='\(resp.expanded)' alts=\(resp.alternatives.count)\n".utf8))
                    self.aiLastError = nil
                    if !resp.shouldExpand || resp.expanded.isEmpty {
                        // AI declined — re-insert the period as a no-op.
                        self.interceptor.cancelExpansion()
                        self.panel.hide()
                        return
                    }
                    self.applyExpansion(
                        compressed: compressed,
                        expanded: resp.expanded,
                        alternatives: resp.alternatives,
                        confidence: resp.confidence
                    )
                case .failure(let err):
                    FileHandle.standardError.write(Data("[appstate] AI failed: \(err.displayMessage)\n".utf8))
                    self.aiLastError = err.displayMessage
                    // Failure — restore the user's period unchanged.
                    self.interceptor.cancelExpansion()
                    let topLeft = CaretLocator.panelTopLeftBelowCaret(panelHeight: 60)
                    self.panel.showError(at: topLeft, message: err.displayMessage)
                    self.scheduleHide(after: 3.5)
                }
            }
        }
    }

    private func applyExpansion(compressed: String,
                                expanded: String,
                                alternatives: [String],
                                confidence: Double) {
        interceptor.applyExpansion(compressed: compressed, expanded: expanded)
        liveExpansion = LiveExpansion(
            compressed: compressed,
            picked: expanded,
            alternatives: alternatives
        )
        lastAlternatives = alternatives
        showAlternativesPanel(confidence: confidence)
    }

    private func showAlternativesPanel(confidence: Double) {
        guard let live = liveExpansion else { return }
        let topLeft = CaretLocator.panelTopLeftBelowCaret(panelHeight: 140)
        panel.showExpanded(
            at: topLeft,
            picked: live.picked,
            alternatives: live.alternatives,
            onSwap: { [weak self] alt in
                Task { @MainActor in self?.swap(to: alt) }
            },
            onUndo: { [weak self] in
                Task { @MainActor in self?.undo() }
            }
        )
        // High confidence → hide quickly; low confidence → linger.
        let linger: TimeInterval = confidence >= 0.85 ? 2.5 : 6.0
        scheduleHide(after: linger)
    }

    private func scheduleHide(after seconds: TimeInterval) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if Task.isCancelled { return }
            await MainActor.run { [weak self] in
                self?.panel.hide()
                self?.liveExpansion = nil
            }
        }
    }

    // MARK: - Swap / undo

    /// Replace the currently-inserted expanded sentence with `alt`.
    /// "Picked sentence + ." is what got injected → delete that many
    /// characters, inject "alt + .".
    private func swap(to alt: String) {
        guard let live = liveExpansion else { return }
        let currentLen = live.picked.count + 1 // "+1" for the period we appended
        interceptor.injectReplacement(deletingChars: currentLen, with: alt + ".")
        liveExpansion?.picked = alt
        lastExpansion = alt
        recordCorrection(compressed: live.compressed, final: alt)
        showAlternativesPanel(confidence: 1.0)
    }

    /// Restore the user's original compressed token + period.
    private func undo() {
        guard let live = liveExpansion else { return }
        let currentLen = live.picked.count + 1
        interceptor.injectReplacement(deletingChars: currentLen, with: live.compressed + ".")
        liveExpansion = nil
        lastExpansion = nil
        lastCompressed = nil
        panel.hide()
        hideTask?.cancel()
    }

    private func recordCorrection(compressed: String, final: String) {
        recentCorrections.removeAll { $0.compressed == compressed }
        recentCorrections.insert((compressed, final), at: 0)
        if recentCorrections.count > 8 { recentCorrections.removeLast() }
    }
}
