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
    /// When true, expand even when the buffered token is a normal English
    /// word. Off by default to keep typing safe.
    @Published var aggressiveMode: Bool = false
    /// Most recent gate-skip reason. Shown in the settings window so the
    /// user can see why an expansion didn't happen.
    @Published var lastGateSkipReason: String? = nil

    // MARK: - Dependencies

    private let interceptor: KeystrokeInterceptor
    private let panel: SuggestionPanel
    private let ai: MiniMaxClient?

    /// Persistent (compressed → final) correction history. Used as
    /// few-shot examples in subsequent expansion requests and re-loaded
    /// from disk on launch.
    private let corrections: CorrectionStore

    /// State needed to build a CorrectionRecord after the user has
    /// either accepted (timeout / swap) or rejected (undo) an expansion.
    private struct PendingRecord {
        let compressed: String
        let generated: String
        let confidence: Double
        let alternatives: [String]
        let contextBefore: String
        let contextAfter: String
        let appName: String?
    }
    private var pendingRecord: PendingRecord?

    /// Set when an expansion has been applied and we're waiting for the
    /// user to either accept it (timeout), swap to an alternative, or undo.
    private struct LiveExpansion {
        let compressed: String
        var picked: String     // currently-inserted sentence (without ".")
        let alternatives: [String]
    }
    private var liveExpansion: LiveExpansion?
    /// Set when AI returned a low-confidence guess and we did NOT apply
    /// it — panel is offering 1/2/3 picks but the user's text is still
    /// the original compressed token + period.
    private struct PendingSuggestion {
        let compressed: String
        let candidates: [String]
    }
    private var pendingSuggestion: PendingSuggestion?
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
        self.corrections = CorrectionStore()

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
            }
        }
        interceptor.didPressArmedKey = { [weak self] key in
            Task { @MainActor [weak self] in self?.handleArmedKey(key) }
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
        // Clear any stale "Expanding…" UI from a prior request whose AI
        // call may still be in flight. If we don't, a gate-skip on this
        // new request would leave the old panel showing forever once
        // the stale result lands and gets dropped by the generation guard.
        if aiInFlight {
            aiInFlight = false
            panel.hide()
        }

        let context = CaretLocator.contextAroundCaret(maxChars: 500)
        let frontApp = NSWorkspace.shared.frontmostApplication
        let bundleID = frontApp?.bundleIdentifier
        let appName = frontApp?.localizedName

        let decision = ExpansionGate.check(
            compressed: compressed,
            contextBefore: context.before,
            contextAfter: context.after,
            focusedAppBundleID: bundleID,
            aggressiveMode: aggressiveMode
        )
        if case .skip(let reason) = decision {
            FileHandle.standardError.write(Data("[appstate] gate skip: \(reason)\n".utf8))
            self.lastGateSkipReason = reason
            interceptor.cancelExpansion()
            return
        }
        self.lastGateSkipReason = nil

        // LOCAL-FIRST PATH. If the input segments cleanly into known
        // English words / contractions / known shorthand, we have a
        // microseconds-fast answer with no API cost. Only fall through
        // to the LLM when local confidence is below threshold.
        let local = LocalPipeline.run(compressed)
        FileHandle.standardError.write(Data("[appstate] local: '\(local.expandedSentence)' conf=\(local.confidence) segs=\(local.segments) unknown=\(local.unknownCount) lat=\(String(format: "%.1f", local.latencyMs))ms\n".utf8))
        if local.confidence >= 0.85, !local.expandedSentence.isEmpty {
            applyLocalExpansion(
                compressed: compressed,
                expanded: local.expandedSentence,
                segments: local.segments,
                contextBefore: context.before,
                contextAfter: context.after,
                appName: appName
            )
            return
        }

        guard let ai else {
            aiLastError = "no API key configured — set MINIMAX_API_KEY in .env"
            interceptor.cancelExpansion()
            return
        }

        let topLeft = CaretLocator.panelTopLeftBelowCaret(panelHeight: 140)
        aiInFlight = true
        panel.showExpanding(at: topLeft, compressed: compressed)
        // Hard deadline: if the AI request hangs or its result is
        // dropped due to a newer generation, force-hide the panel after
        // a generous window so we never have stale "Expanding…" UI.
        scheduleHide(after: 12.0)

        let relevantCorrections = corrections.relevant(forCompressed: compressed, appName: appName, limit: 5)

        let req = ExpansionRequest(
            compressedInput: compressed,
            contextBefore: context.before,
            contextAfter: context.after,
            appName: appName,
            recentCorrections: relevantCorrections,
            styleNotes: styleNotes
        )

        Task { [weak self] in
            let result = await ai.expand(req)
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard self.generation == myGen else { return }
                self.aiInFlight = false
                switch result {
                case .success(let rawResp):
                    let resp = LocalReranker.rerank(
                        rawResp,
                        compressedInput: compressed,
                        recentCorrections: relevantCorrections
                    )
                    FileHandle.standardError.write(Data("[appstate] AI ok: should=\(resp.shouldExpand) conf=\(resp.confidence) expanded='\(resp.expanded)' alts=\(resp.alternatives.count)\n".utf8))
                    self.aiLastError = nil
                    if !resp.shouldExpand || resp.expanded.isEmpty {
                        self.interceptor.cancelExpansion()
                        self.panel.hide()
                        return
                    }
                    self.pendingRecord = PendingRecord(
                        compressed: compressed,
                        generated: resp.expanded,
                        confidence: resp.confidence,
                        alternatives: resp.alternatives,
                        contextBefore: context.before,
                        contextAfter: context.after,
                        appName: appName
                    )
                    self.routeByConfidence(
                        compressed: compressed,
                        expanded: resp.expanded,
                        alternatives: resp.alternatives,
                        confidence: resp.confidence
                    )
                case .failure(let err):
                    FileHandle.standardError.write(Data("[appstate] AI failed: \(err.displayMessage)\n".utf8))
                    self.aiLastError = err.displayMessage
                    self.interceptor.cancelExpansion()
                    let topLeft = CaretLocator.panelTopLeftBelowCaret(panelHeight: 60)
                    self.panel.showError(at: topLeft, message: err.displayMessage)
                    self.scheduleHide(after: 3.5)
                }
            }
        }
    }

    /// Four confidence bands:
    ///   • ≥0.85 — auto-replace, short panel (2.5s)
    ///   • 0.65–0.84 — auto-replace, longer panel (6s), arm 1/2/3 swap + Cmd+Z undo
    ///   • 0.45–0.64 — DON'T replace, show "did you mean…" panel, arm 1/2/3 to apply
    ///   • <0.45 — do nothing, restore the period and hide the panel
    private func routeByConfidence(compressed: String,
                                   expanded: String,
                                   alternatives: [String],
                                   confidence: Double) {
        if confidence < 0.45 {
            FileHandle.standardError.write(Data("[appstate] very low conf (\(confidence)) — silent\n".utf8))
            interceptor.cancelExpansion()
            panel.hide()
            pendingRecord = nil
            return
        }
        if confidence < 0.65 {
            // Don't touch the text. The interceptor already swallowed
            // the "." — put it back so the user's sentence isn't damaged.
            interceptor.cancelExpansion()
            let pool = ([expanded] + alternatives).reduce(into: [String]()) { acc, s in
                if !acc.contains(s) && !s.isEmpty { acc.append(s) }
            }
            pendingSuggestion = PendingSuggestion(compressed: compressed, candidates: pool)
            liveExpansion = nil
            lastAlternatives = pool
            let topLeft = CaretLocator.panelTopLeftBelowCaret(panelHeight: 140)
            panel.showSuggestion(
                at: topLeft,
                compressed: compressed,
                candidates: pool,
                onPick: { [weak self] idx in
                    Task { @MainActor in self?.applySuggestion(at: idx) }
                },
                onDismiss: { [weak self] in
                    Task { @MainActor in self?.dismissSuggestion() }
                }
            )
            interceptor.armAlternativeKeys(seconds: 6)
            scheduleHide(after: 6.0)
            return
        }

        // 0.65+ → apply.
        applyExpansion(compressed: compressed,
                       expanded: expanded,
                       alternatives: alternatives,
                       confidence: confidence)
    }

    /// Fast path: local pipeline produced a high-confidence answer.
    /// Inject, persist a CorrectionRecord with `appName` annotated as
    /// "local", and arm Cmd+Z so the user can still bail if we got it
    /// wrong.
    private func applyLocalExpansion(compressed: String,
                                     expanded: String,
                                     segments: [String],
                                     contextBefore: String,
                                     contextAfter: String,
                                     appName: String?) {
        interceptor.applyExpansion(compressed: compressed, expanded: expanded)
        liveExpansion = LiveExpansion(
            compressed: compressed,
            picked: expanded,
            alternatives: []
        )
        pendingSuggestion = nil
        lastAlternatives = []
        let pending = PendingRecord(
            compressed: compressed,
            generated: expanded,
            confidence: 0.95,
            alternatives: [],
            contextBefore: contextBefore,
            contextAfter: contextAfter,
            appName: appName.map { "\($0) (local)" } ?? "local"
        )
        pendingRecord = pending
        showAlternativesPanel(confidence: 0.95)
        interceptor.armUndoKey(seconds: 6)
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
        pendingSuggestion = nil
        lastAlternatives = alternatives
        showAlternativesPanel(confidence: confidence)
        // Always allow Cmd+Z immediately after an expansion.
        interceptor.armUndoKey(seconds: 6)
        // Allow numeric swap to an alternative for the same window.
        interceptor.armAlternativeKeys(seconds: 6)
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
        let linger: TimeInterval = confidence >= 0.85 ? 2.5 : 6.0
        scheduleHide(after: linger)
    }

    private func scheduleHide(after seconds: TimeInterval) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if Task.isCancelled { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                // If the user let the panel time out, treat the current
                // expansion as accepted as-is and write the correction.
                if let live = self.liveExpansion, let pending = self.pendingRecord {
                    self.persistCorrection(
                        from: pending,
                        finalSentence: live.picked,
                        pickedAlt: nil,
                        rejected: live.alternatives
                    )
                    self.pendingRecord = nil
                }
                self.panel.hide()
                self.liveExpansion = nil
                self.pendingSuggestion = nil
                self.interceptor.disarmFollowUpKeys()
            }
        }
    }

    private func persistCorrection(from p: PendingRecord,
                                   finalSentence: String,
                                   pickedAlt: String?,
                                   rejected: [String]) {
        let rec = CorrectionRecord(
            compressedInput: p.compressed,
            generatedSentence: p.generated,
            finalUserSentence: finalSentence,
            confidence: p.confidence,
            alternatives: p.alternatives,
            pickedAlternative: pickedAlt,
            rejectedAlternatives: rejected,
            contextBefore: p.contextBefore,
            contextAfter: p.contextAfter,
            appName: p.appName,
            timestamp: Date()
        )
        corrections.record(rec)
    }

    // MARK: - Armed-key callbacks (from interceptor)

    private func handleArmedKey(_ key: KeystrokeInterceptor.ArmedKey) {
        switch key {
        case .undo:
            undo()
        case .escape:
            if pendingSuggestion != nil {
                dismissSuggestion()
            } else {
                panel.hide()
                hideTask?.cancel()
            }
        case .alt(let i):
            let idx = i - 1
            if let pending = pendingSuggestion, idx >= 0, idx < pending.candidates.count {
                applySuggestion(at: idx)
            } else if let live = liveExpansion, idx >= 0, idx < live.alternatives.count {
                swap(to: live.alternatives[idx])
            }
        }
    }

    /// Apply one of the low-confidence "did you mean…" candidates.
    /// Text was not modified yet, so we delete the (compressed + ".")
    /// the interceptor restored and inject the pick.
    private func applySuggestion(at idx: Int) {
        guard let pending = pendingSuggestion,
              idx >= 0, idx < pending.candidates.count else { return }
        let pick = pending.candidates[idx]
        interceptor.injectReplacement(
            deletingChars: pending.compressed.count + 1,
            with: pick + "."
        )
        let rejected = pending.candidates.filter { $0 != pick }
        liveExpansion = LiveExpansion(
            compressed: pending.compressed,
            picked: pick,
            alternatives: rejected
        )
        pendingSuggestion = nil
        lastCompressed = pending.compressed
        lastExpansion = pick
        lastAlternatives = rejected
        if let p = pendingRecord {
            persistCorrection(from: p, finalSentence: pick,
                              pickedAlt: pick == p.generated ? nil : pick,
                              rejected: rejected)
            pendingRecord = nil
        }
        showAlternativesPanel(confidence: 1.0)
        interceptor.armUndoKey(seconds: 6)
    }

    private func dismissSuggestion() {
        pendingSuggestion = nil
        panel.hide()
        hideTask?.cancel()
        interceptor.disarmFollowUpKeys()
    }

    // MARK: - Swap / undo

    private func swap(to alt: String) {
        guard let live = liveExpansion else { return }
        let currentLen = live.picked.count + 1
        interceptor.injectReplacement(deletingChars: currentLen, with: alt + ".")
        let rejected = live.alternatives.filter { $0 != alt } + (live.picked != alt ? [live.picked] : [])
        liveExpansion?.picked = alt
        lastExpansion = alt
        if let p = pendingRecord {
            persistCorrection(from: p, finalSentence: alt, pickedAlt: alt, rejected: rejected)
            pendingRecord = nil
        }
        showAlternativesPanel(confidence: 1.0)
        interceptor.armUndoKey(seconds: 6)
    }

    private func undo() {
        guard let live = liveExpansion else { return }
        let currentLen = live.picked.count + 1
        interceptor.injectReplacement(deletingChars: currentLen, with: live.compressed + ".")
        // An undo means "you got this wrong" — record an empty final
        // sentence so the model learns NOT to repeat that expansion.
        if let p = pendingRecord {
            persistCorrection(from: p,
                              finalSentence: "",
                              pickedAlt: nil,
                              rejected: [p.generated] + p.alternatives)
            pendingRecord = nil
        }
        liveExpansion = nil
        lastExpansion = nil
        lastCompressed = nil
        panel.hide()
        hideTask?.cancel()
        interceptor.disarmFollowUpKeys()
    }
}
