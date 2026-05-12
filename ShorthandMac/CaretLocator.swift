import AppKit
import ApplicationServices

/// Asks the Accessibility API where the currently-focused text caret is on
/// screen. Some apps (Terminal, Electron-based apps, some browsers) refuse
/// to expose this — in that case we fall back to the mouse cursor.
enum CaretLocator {

    static func currentCaretRect() -> CGRect? {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
                systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef
              ) == .success,
              let focusedRef else { return nil }
        let focused = focusedRef as! AXUIElement

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
                focused, kAXSelectedTextRangeAttribute as CFString, &rangeRef
              ) == .success,
              let rangeRef else { return nil }
        let rangeValue = rangeRef as! AXValue

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
                focused,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                rangeValue,
                &boundsRef
              ) == .success,
              let boundsRef else { return nil }

        var rect = CGRect.zero
        AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect)
        // Some apps return a zero-width / zero-height rect for an empty
        // selection; that's still useful as a position anchor.
        return rect
    }

    /// Top-left position to anchor the suggestion panel — in NSWindow
    /// coordinates (origin at the bottom-left of the *primary* screen,
    /// since that's what `setFrameTopLeftPoint` expects).
    static func panelTopLeftBelowCaret(panelHeight: CGFloat) -> NSPoint {
        if let rect = currentCaretRect(), let screen = NSScreen.main {
            // AX gives screen coordinates with the origin at the top-left
            // of the primary screen; AppKit windows use bottom-left.
            let screenHeight = screen.frame.height
            let topLeftY = screenHeight - rect.maxY - 6
            return NSPoint(x: rect.minX, y: topLeftY)
        }
        // Fallback: anchor near the mouse cursor.
        let mouse = NSEvent.mouseLocation
        return NSPoint(x: mouse.x + 12, y: mouse.y - 12)
    }

    /// Returns (before, after) text around the caret in the focused field,
    /// each truncated to `maxChars`. Many apps return the entire value via
    /// `kAXValueAttribute`; we read it and slice around the selected range.
    /// Returns ("", "") when AX isn't available for the focused element.
    static func contextAroundCaret(maxChars: Int = 120) -> (before: String, after: String) {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
                systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef
              ) == .success,
              let focusedRef else { return ("", "") }
        let focused = focusedRef as! AXUIElement

        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
                focused, kAXValueAttribute as CFString, &valueRef
              ) == .success,
              let text = valueRef as? String else { return ("", "") }

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
                focused, kAXSelectedTextRangeAttribute as CFString, &rangeRef
              ) == .success,
              let rangeRef else { return ("", "") }
        var cfRange = CFRange()
        AXValueGetValue(rangeRef as! AXValue, .cfRange, &cfRange)

        let ns = text as NSString
        let loc = max(0, min(cfRange.location, ns.length))
        let beforeLen = min(maxChars, loc)
        let afterStart = loc + max(0, cfRange.length)
        let afterLen = min(maxChars, max(0, ns.length - afterStart))
        let before = beforeLen > 0
            ? ns.substring(with: NSRange(location: loc - beforeLen, length: beforeLen))
            : ""
        let after = afterLen > 0
            ? ns.substring(with: NSRange(location: afterStart, length: afterLen))
            : ""
        return (before, after)
    }
}
