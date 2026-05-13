import Foundation
import CoreGraphics
import ApplicationServices

/// Installs a global keyboard event tap. Accumulates a "compact token" —
/// the run of letter keystrokes since the last word boundary (space,
/// return, tab, escape, arrow, modifier-shortcut).
///
/// On `.`:
///   • If the buffered token is 2–80 letters AND no spaces have been
///     typed inside it (i.e. it is plausibly a compact shorthand token),
///     the period is consumed and `didRequestExpansion` is fired with
///     the token. AppState then calls the AI and reports back via
///     `applyExpansion(...)`.
///   • Otherwise (buffer empty / too short / too long / contained a
///     space), the period passes through unchanged. Normal writing is
///     never touched.
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

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let injectedSource: CGEventSource?
    private let injectionSentinel: Int64 = 0x5348_4F52_5448  // "SHORTH"

    /// Letters typed since the last word boundary (lowercased).
    private var buffer: String = ""

    /// Min/max length for a token to be considered shorthand. Below the
    /// floor we treat it as a typo and let "." through normally.
    var minShorthandLength = 2
    var maxShorthandLength = 80

    /// Fired whenever the buffer changes — for live UI feedback.
    var didBufferChange: ((String) -> Void)?
    /// Fired when the user types "." on a plausible shorthand token. The
    /// interceptor has already consumed the period; AppState should call
    /// `applyExpansion(...)` once it has a result (or call
    /// `cancelExpansion(...)` to reinsert the period unchanged).
    var didRequestExpansion: ((String) -> Void)?
    /// Fired after a successful inject — for analytics / history.
    var didExpand: ((_ compressed: String, _ expanded: String) -> Void)?

    /// Follow-up keys after an expansion: numeric alternative pick, Esc
    /// to dismiss, Cmd+Z to undo. AppState arms these for a few seconds
    /// after a successful expansion (or a low-confidence suggestion).
    enum ArmedKey { case alt(Int), escape, undo }
    var didPressArmedKey: ((ArmedKey) -> Void)?
    private var altKeysDeadline: Date?
    private var undoKeyDeadline: Date?

    /// Arm 1/2/3 + Esc capture for `seconds`. While armed, those keys are
    /// consumed (not delivered to the host app) and reported via
    /// `didPressArmedKey`. Any non-matching keystroke disarms gracefully.
    func armAlternativeKeys(seconds: TimeInterval = 5) {
        altKeysDeadline = Date().addingTimeInterval(seconds)
    }

    /// Arm Cmd+Z capture for `seconds`. While armed, Cmd+Z is consumed
    /// and reported via `didPressArmedKey(.undo)` so AppState can do its
    /// own restore rather than letting the host's undo run.
    func armUndoKey(seconds: TimeInterval = 5) {
        undoKeyDeadline = Date().addingTimeInterval(seconds)
    }

    func disarmFollowUpKeys() {
        altKeysDeadline = nil
        undoKeyDeadline = nil
    }

    init() {
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
        FileHandle.standardError.write(Data("[interceptor] tap installed\n".utf8))
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

    // MARK: - Public

    /// Replace `deletingChars` characters before the caret with `text`.
    /// Used both when expansion succeeds and when the user picks an
    /// alternative or undoes.
    func injectReplacement(deletingChars count: Int, with text: String) {
        guard let source = injectedSource else { return }
        for _ in 0..<count {
            CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true)?
                .post(tap: .cgAnnotatedSessionEventTap)
            CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: false)?
                .post(tap: .cgAnnotatedSessionEventTap)
        }
        guard !text.isEmpty else { return }
        let utf16 = Array(text.utf16)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        down?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        down?.post(tap: .cgAnnotatedSessionEventTap)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        up?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    /// Successful expansion. The interceptor already swallowed the "."
    /// when it fired the request — so we delete `compressed.count` chars
    /// (the shorthand letters) and inject `expanded + "."`.
    func applyExpansion(compressed: String, expanded: String) {
        clearBuffer()
        injectReplacement(deletingChars: compressed.count, with: expanded + ".")
        DispatchQueue.main.async { [weak self] in
            self?.didExpand?(compressed, expanded)
        }
    }

    /// AI declined to expand (or failed). Reinsert the period that the
    /// interceptor swallowed so the user's sentence is unchanged.
    func cancelExpansion() {
        clearBuffer()
        injectReplacement(deletingChars: 0, with: ".")
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

        // Follow-up-key capture (1/2/3, Esc, Cmd+Z). These are armed by
        // AppState for a few seconds after an expansion; we consume the
        // matching keystroke and report it. Any non-matching key disarms
        // gracefully and falls through to normal processing.
        switch checkArmedKeys(keyCode: keyCode, flags: event.flags) {
        case .consume: return nil
        case .passThrough: return Unmanaged.passUnretained(event)
        case .noMatch: break
        }

        // Backspace: pop one, pass through.
        if keyCode == 0x33 {
            if !buffer.isEmpty {
                buffer.removeLast()
                emitBuffer()
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
        if s == "." {
            let len = buffer.count
            FileHandle.standardError.write(Data("[interceptor] '.' pressed, buffer='\(buffer)' (\(len) chars)\n".utf8))
            if len >= minShorthandLength && len <= maxShorthandLength {
                let compressed = buffer
                clearBuffer()
                DispatchQueue.main.async { [weak self] in
                    self?.didRequestExpansion?(compressed)
                }
                return nil   // consume the "."
            }
            clearBuffer()
            return Unmanaged.passUnretained(event)
        }

        // Letter accumulation.
        if s.count == 1, let scalar = s.unicodeScalars.first,
           CharacterSet.letters.contains(scalar) {
            buffer.append(Character(s.lowercased()))
            if buffer.count > maxShorthandLength + 4 {
                // Past the upper bound it's not a shorthand candidate
                // anymore — drop the buffer so the next "." doesn't
                // surprise the user.
                clearBuffer()
                return Unmanaged.passUnretained(event)
            }
            emitBuffer()
            return Unmanaged.passUnretained(event)
        }

        // Anything else (space, digits, other punctuation) is a word
        // boundary — normal writing should never be transformed.
        clearBuffer()
        return Unmanaged.passUnretained(event)
    }

    private enum ArmedResult { case consume, passThrough, noMatch }

    private func checkArmedKeys(keyCode: Int64, flags: CGEventFlags) -> ArmedResult {
        let now = Date()
        let undoArmed = (undoKeyDeadline.map { now < $0 } ?? false)
        let altsArmed = (altKeysDeadline.map { now < $0 } ?? false)
        if !undoArmed { undoKeyDeadline = nil }
        if !altsArmed { altKeysDeadline = nil }
        if !undoArmed && !altsArmed { return .noMatch }

        let hasCmd = !flags.intersection(.maskCommand).isEmpty
        let hasOther = !flags.intersection([.maskControl, .maskAlternate]).isEmpty

        // Cmd+Z → undo (only).
        if undoArmed, hasCmd, !hasOther, keyCode == 0x06 {
            undoKeyDeadline = nil
            altKeysDeadline = nil
            DispatchQueue.main.async { [weak self] in
                self?.didPressArmedKey?(.undo)
            }
            return .consume
        }

        // Plain 1 / 2 / 3 → alternative pick.
        if altsArmed, !hasCmd, !hasOther {
            let idx: Int? = {
                switch keyCode {
                case 0x12: return 1
                case 0x13: return 2
                case 0x14: return 3
                default: return nil
                }
            }()
            if let idx {
                altKeysDeadline = nil
                undoKeyDeadline = nil
                DispatchQueue.main.async { [weak self] in
                    self?.didPressArmedKey?(.alt(idx))
                }
                return .consume
            }
        }

        // Esc → dismiss.
        if altsArmed, keyCode == 0x35 {
            altKeysDeadline = nil
            undoKeyDeadline = nil
            DispatchQueue.main.async { [weak self] in
                self?.didPressArmedKey?(.escape)
            }
            return .consume
        }

        // A modifier-bearing keystroke that isn't our Cmd+Z — disarm undo
        // (user is doing something else). Don't disarm alts.
        if hasCmd || hasOther {
            undoKeyDeadline = nil
            return .noMatch
        }

        // Plain key that isn't 1/2/3/Esc — disarm alts (user is moving
        // on) but keep undo armed; Cmd+Z is still meaningful.
        altKeysDeadline = nil
        return .noMatch
    }

    private func clearBuffer() {
        if !buffer.isEmpty {
            buffer = ""
            emitBuffer()
        }
    }

    private func emitBuffer() {
        let snap = buffer
        DispatchQueue.main.async { [weak self] in
            self?.didBufferChange?(snap)
        }
    }
}
