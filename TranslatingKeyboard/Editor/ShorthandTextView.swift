import SwiftUI
import UIKit

/// UIViewRepresentable wrapper around UITextView, used so the editor can
/// observe range-level edits (needed to track the pending correction's
/// range as the user revises it). SwiftUI's `TextEditor` doesn't expose
/// shouldChangeTextIn — UITextView's delegate does.
struct ShorthandTextView: UIViewRepresentable {

    @Binding var text: String
    let viewModel: EditorViewModel

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = .systemFont(ofSize: 18)
        tv.isScrollEnabled = true
        tv.alwaysBounceVertical = true
        tv.keyboardDismissMode = .interactive
        // Shorthand is alpha+`.`; smart substitutions get in the way.
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.smartInsertDeleteType = .no
        tv.text = text
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // Only push state into the view when SwiftUI's truth diverged from
        // the textView (avoids a feedback loop with delegate callbacks).
        if uiView.text != text {
            let cursor = uiView.selectedRange
            uiView.text = text
            // Clamp the prior cursor against the new text length so we
            // don't crash on programmatic replacements.
            let ns = uiView.text as NSString
            let safeLocation = min(cursor.location, ns.length)
            uiView.selectedRange = NSRange(location: safeLocation, length: 0)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        let parent: ShorthandTextView

        init(_ parent: ShorthandTextView) {
            self.parent = parent
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            parent.viewModel.willReplaceText(in: range, with: text)
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.viewModel.textDidChange(in: textView)
        }
    }
}
