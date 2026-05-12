import SwiftUI

struct KeyboardRootView: View {
    @ObservedObject var model: KeyboardModel

    private let row1 = ["q","w","e","r","t","y","u","i","o","p"]
    private let row2 = ["a","s","d","f","g","h","j","k","l"]
    private let row3 = ["z","x","c","v","b","n","m"]

    private var keyHeight: CGFloat { 42 }
    private var rowSpacing: CGFloat { 6 }
    private var keySpacing: CGFloat { 4 }

    var body: some View {
        VStack(spacing: rowSpacing) {
            previewBar

            // Row 1: 10 letters
            HStack(spacing: keySpacing) {
                ForEach(row1, id: \.self) { letter in
                    KeyView(displayLabel(letter)) { model.letterTapped(letter) }
                }
            }
            .frame(height: keyHeight)

            // Row 2: 9 letters, slightly inset
            HStack(spacing: keySpacing) {
                Spacer(minLength: 0).frame(width: 14)
                ForEach(row2, id: \.self) { letter in
                    KeyView(displayLabel(letter)) { model.letterTapped(letter) }
                }
                Spacer(minLength: 0).frame(width: 14)
            }
            .frame(height: keyHeight)

            // Row 3: shift, 7 letters, delete
            HStack(spacing: keySpacing) {
                KeyView(
                    model.isCapsLock ? "⇪" : "⇧",
                    isSpecial: true,
                    isActive: model.isShifted || model.isCapsLock
                ) {
                    model.shiftTapped()
                }
                .frame(width: 38)

                ForEach(row3, id: \.self) { letter in
                    KeyView(displayLabel(letter)) { model.letterTapped(letter) }
                }

                KeyView("⌫", isSpecial: true) { model.deleteTapped() }
                    .frame(width: 38)
            }
            .frame(height: keyHeight)

            // Row 4: globe, space, period (trigger), return
            HStack(spacing: keySpacing) {
                KeyView("🌐", isSpecial: true) { model.globeTapped() }
                    .frame(width: 38)
                KeyView("space", isSpecial: true) { model.spaceTapped() }
                    .frame(maxWidth: .infinity)
                KeyView(".", isSpecial: true) { model.periodTapped() }
                    .frame(width: 44)
                KeyView("return", isSpecial: true) { model.returnTapped() }
                    .frame(width: 64)
            }
            .frame(height: keyHeight)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .background(Color(UIColor.systemGroupedBackground))
    }

    @ViewBuilder
    private var previewBar: some View {
        if let summary = model.lastExpansionSummary {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                    .font(.caption)
                    .foregroundStyle(.tint)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
        } else {
            // Reserve a tiny strip so layout doesn't jump on the first
            // expansion.
            Color.clear.frame(height: 4)
        }
    }

    private func displayLabel(_ letter: String) -> String {
        (model.isShifted || model.isCapsLock) ? letter.uppercased() : letter
    }
}
