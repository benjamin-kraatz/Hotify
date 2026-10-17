import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Plain text for code, such as a compose file: monospaced, and with nothing that rewrites what is typed.
///
/// SwiftUI's `TextEditor` has no switch for smart quotes or dashes, and either one breaks YAML without a sign. So this
/// wraps the platform's text view with every substitution off. Tab indents with two spaces, since YAML refuses tabs, and
/// Return keeps the line's indentation. Find works as it does in any text view. On the Mac, Escape leaves the editor.
struct CodeEditor: View {
    @Binding var text: String
    var isEditable = true
    /// Read by VoiceOver, since the editor has no visible label of its own.
    var accessibilityLabel: String

    var body: some View {
        CodeTextView(text: $text, isEditable: isEditable)
            .accessibilityLabel(accessibilityLabel)
    }

    /// The text to insert for a new line after `line`: a line break and the line's leading spaces.
    static func newline(after line: Substring) -> String {
        "\n" + line.prefix { $0 == " " }
    }

    /// Two spaces, YAML's usual step, in place of a tab.
    static let indent = "  "
}

#if os(macOS)
private struct CodeTextView: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 6, height: 10)
        textView.string = text
        textView.isEditable = isEditable
        textView.isSelectable = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.isEditable = isEditable
        // Only a change from outside, such as a revert. Setting the same text would move the caret to the end.
        if textView.string != text {
            let selection = textView.selectedRanges
            textView.string = text
            let length = (text as NSString).length
            textView.selectedRanges = selection.compactMap { value in
                let range = value.rangeValue
                return range.location <= length ? value : nil
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertTab(_:)):
                textView.insertText(CodeEditor.indent, replacementRange: textView.selectedRange())
                return true
            case #selector(NSResponder.insertNewline(_:)):
                let string = textView.string as NSString
                let caret = textView.selectedRange().location
                let line = string.substring(with: string.lineRange(for: NSRange(location: caret, length: 0)))
                textView.insertText(
                    CodeEditor.newline(after: Substring(line)), replacementRange: textView.selectedRange())
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                // A text view opens word completion on Escape. Here it leaves the editor, so the next Escape can go
                // back the way any other screen does.
                textView.window?.makeFirstResponder(nil)
                return true
            default:
                return false
            }
        }
    }
}
#else
private struct CodeTextView: UIViewRepresentable {
    @Binding var text: String
    var isEditable: Bool

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.spellCheckingType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.inlinePredictionType = .no
        textView.dataDetectorTypes = []
        textView.keyboardType = .asciiCapable
        textView.isFindInteractionEnabled = true
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.font = UIFontMetrics(forTextStyle: .body)
            .scaledFont(for: .monospacedSystemFont(ofSize: 15, weight: .regular))
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .label
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        textView.text = text
        textView.isEditable = isEditable
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.text = $text
        textView.isEditable = isEditable
        if textView.text != text {
            let selection = textView.selectedRange
            textView.text = text
            if selection.location <= (text as NSString).length {
                textView.selectedRange = selection
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText: String) -> Bool {
            let replacement: String
            switch replacementText {
            case "\t":
                replacement = CodeEditor.indent
            case "\n":
                let string = textView.text as NSString
                let line = string.substring(with: string.lineRange(for: NSRange(location: range.location, length: 0)))
                replacement = CodeEditor.newline(after: Substring(line))
            default:
                return true
            }
            // Through the text input system, so undo and the caret follow as if it had been typed.
            guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
                let end = textView.position(from: start, offset: range.length),
                let textRange = textView.textRange(from: start, to: end)
            else { return true }
            textView.replace(textRange, withText: replacement)
            return false
        }
    }
}
#endif

#Preview {
    @Previewable @State var text = """
        services:
          web:
            image: 'nginx:1.27'
            environment:
              - 'SERVICE_URL_WEB_80'
        """
    CodeEditor(text: $text, accessibilityLabel: "Compose file")
        .frame(width: 520, height: 280)
        .well()
        .padding()
}
