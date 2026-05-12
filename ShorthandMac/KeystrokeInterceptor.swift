import Foundation
import CoreGraphics
import ApplicationServices

/// Installs a global keyboard event tap (the same mechanism Karabiner /
/// TextExpander use). Accumulates the current run of letter keystrokes
/// (the "buffer"); on every change the buffer is decoded into the top-3
/// 1-letter-prefix sentence candidates and emitted via `didUpdate`.
///
/// On `.`:  the top suggestion (if any) is auto-applied — the buffer
/// letters are deleted via synthesized backspaces and the expanded
/// sentence + "." is injected as a single Unicode keystroke. If there's
/// no usable suggestion, the period passes through normally.
///
/// On click in the suggestion panel: the caller invokes
/// `applySuggestion(_:withTrailingPeriod:)` for the chosen index.
final class KeystrokeInterceptor {

    enum InterceptorError: Error, LocalizedError {
        case tapCreationFailed
        var errorDescription: String? {
            switch self {
            case .tapCreationFailed:
                return "Failed to install the keyboard event tap. Accessibility permission probably not granted to this binary."
            }
        }
    }

    private let expander: SentenceExpander
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let injectedSource: CGEventSource?
    private let injectionSentinel: Int64 = 0x5348_4F52_5448  // "SHORTH"

    /// Letters typed since the last word boundary (lowercased). Mutated
    /// only on the event-tap runloop thread (main).
    private var buffer: String = ""
    /// Latest live suggestion produced by the local decoder. Kept around
    /// so a later "." press can auto-apply #1 without re-decoding.
    private var latest: SentenceExpander.LiveSuggestion = .init(sentences: [], confidence: 0, tokens: [])
    /// `1` or `2` — controls which liveSuggest mode the interceptor asks
    /// the expander for. AppState writes this whenever the setting changes.
    var prefixLength: Int = 2
    /// When non-empty, period auto-apply prefers these sentences over the
    /// interceptor's local-decoder `latest`. AppState writes it to the AI
    /// candidates once they arrive, so a "." after AI-replaced rows
    /// applies the AI's top guess.
    var overrideSuggestions: [String] = []
    /// When true, the interceptor refuses to auto-apply local-only
    /// suggestions on "." (AI must have produced an override first).
    /// AppState sets this when the user has MiniMax configured.
    var aiOnly: Bool = false

    /// (buffer, suggestions). Posted on the main queue. The UI uses this
    /// both to show the panel and to refresh its row content.
    var didUpdate: ((String, [String]) -> Void)?
    /// Called after a successful inject (period or click). For analytics.
    var didExpand: ((String, String) -> Void)?

    init(expander: SentenceExpander) {
        self.expander = expander
        let src = CGEventSource(stateID: .privateState)
        src?.userData = 0x5348_4F52_5448
        self.injectedSource = src
    }

    // MARK: - Lifecycle

    func start() throws {
        guard tap == nil else { return }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<KeystrokeInterceptor>.fromOpaque(refcon).takeUnretainedValue()
                return me.handle(type: type, event: event)
            },
            userInfo: refcon
        ) else {
            throw InterceptorError.tapCreationFailed
        }

        tap = port
        runLoopSource = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    func stop() {
        if let port = tap { CGEvent.tapEnable(tap: port, enable: false) }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        clearBuffer()
    }

    // MARK: - Public — called from the suggestion panel

    /// Apply the suggestion at index `pickedIndex`. Prefers
    /// `overrideSuggestions` (set by AppState when AI has reranked)
    /// over the interceptor's own local-decoder result.
    func applySuggestion(pickedIndex idx: Int, withTrailingPeriod: Bool) {
        let pool = overrideSuggestions.isEmpty ? latest.sentences : overrideSuggestions
        guard idx >= 0, idx < pool.count else { return }
        let sentence = pool[idx]
        let bufferLen = buffer.count
        let text = withTrailingPeriod ? sentence + "." : sentence
        let original = buffer
        clearBuffer()
        injectReplacement(deletingChars: bufferLen, with: text)
        DispatchQueue.main.async { [weak self] in
            self?.didExpand?(original, sentence)
        }
    }

    // MARK: - Callback

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Ignore our own injected events.
        let srcUD = event.getIntegerValueField(.eventSourceUserData)
        if srcUD == injectionSentinel {
            return Unmanaged.passUnretained(event)
        }
        if type == .tapDisabledByTimeout {
            if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if type == .tapDisabledByUserInput {
            return Unmanaged.passUnretained(event)
        }
        if type == .flagsChanged {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Backspace: pop one, pass through, refresh suggestions.
        if keyCode == 0x33 {
            if !buffer.isEmpty {
                buffer.removeLast()
                refreshSuggestions()
            }
            return Unmanaged.passUnretained(event)
        }
        // Return / Tab / Escape / arrows: word boundary, clear.
        if keyCode == 0x24 || keyCode == 0x30 || keyCode == 0x35 ||
           (keyCode >= 0x7B && keyCode <= 0x7E) {
            clearBuffer()
            return Unmanaged.passUnretained(event)
        }

        // Skip if Cmd/Ctrl/Opt is held — those keystrokes are shortcuts.
        let modifierKeys: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]
        if event.flags.intersection(modifierKeys).rawValue != 0 {
            clearBuffer()
            return Unmanaged.passUnretained(event)
        }

        // Decode this event's unicode character.
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        guard length > 0 else {
            clearBuffer()
            return Unmanaged.passUnretained(event)
        }
        let s = String(utf16CodeUnits: chars, count: length)

        // The "." trigger.
        //   - When AI is configured (aiOnly): only auto-apply if AI has
        //     produced an override list for the current buffer.
        //   - When AI isn't configured: fall back to the local pool.
        if s == "." {
            let pool: [String]
            if aiOnly {
                pool = overrideSuggestions
            } else {
                pool = overrideSuggestions.isEmpty ? latest.sentences : overrideSuggestions
            }
            if !pool.isEmpty, buffer.count >= 2 {
                applySuggestion(pickedIndex: 0, withTrailingPeriod: true)
                return nil   // consume the "."
            }
            clearBuffer()
            return Unmanaged.passUnretained(event)
        }

        // Letter accumulation — one char per token in the live decoder.
        if s.count == 1, let scalar = s.unicodeScalars.first,
           CharacterSet.letters.contains(scalar) {
            buffer.append(Character(s.lowercased()))
            if buffer.count > 40 { buffer = String(buffer.suffix(40)) }
            refreshSuggestions()
            return Unmanaged.passUnretained(event)
        }

        // Anything else (space, digits, other punctuation) clears.
        clearBuffer()
        return Unmanaged.passUnretained(event)
    }

    private func clearBuffer() {
        if !buffer.isEmpty || !latest.sentences.isEmpty {
            buffer = ""
            latest = .init(sentences: [], confidence: 0, tokens: [])
            let snap = buffer
            DispatchQueue.main.async { [weak self] in
                self?.didUpdate?(snap, [])
            }
        }
    }

    private func refreshSuggestions() {
        latest = expander.liveSuggest(buffer: buffer, prefixLength: prefixLength, count: 3)
        let buf = buffer
        let s = latest.sentences
        DispatchQueue.main.async { [weak self] in
            self?.didUpdate?(buf, s)
        }
    }

    // MARK: - Synthesis

    private func injectReplacement(deletingChars count: Int, with text: String) {
        guard let source = injectedSource else { return }
        for _ in 0..<count {
            CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true)?
                .post(tap: .cgAnnotatedSessionEventTap)
            CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: false)?
                .post(tap: .cgAnnotatedSessionEventTap)
        }
        let utf16 = Array(text.utf16)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        down?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        down?.post(tap: .cgAnnotatedSessionEventTap)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        up?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
