import SwiftUI

/// One key on the keyboard. Kept layout-only — the parent decides what to
/// do on tap and what to draw.
struct KeyView: View {
    let label: String
    /// `true` for non-letter keys (shift, delete, return, space, …). They
    /// render with a darker fill so the letter row visually pops.
    let isSpecial: Bool
    /// Selected/active state — used by shift/caps lock.
    var isActive: Bool = false
    let action: () -> Void

    init(_ label: String, isSpecial: Bool = false, isActive: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.isSpecial = isSpecial
        self.isActive = isActive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 17, weight: isSpecial ? .medium : .regular))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(background)
                .cornerRadius(5)
        }
        .buttonStyle(KeyPressStyle())
    }

    private var background: Color {
        if isActive { return Color(UIColor.systemBlue).opacity(0.25) }
        if isSpecial { return Color(UIColor.systemGray3) }
        return Color(UIColor.systemBackground)
    }
}

/// Tiny press-style: dims the background on highlight so taps feel responsive.
private struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1.0)
    }
}
