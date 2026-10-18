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
/// On iOS, where the keyboard has no Tab, a bar above it indents, outdents, and puts the keyboard away.
struct CodeEditor: View {
    @Binding var text: String
    var isEditable = true
    /// Read by VoiceOver, since the editor has no visible label of its own.
    var accessibilityLabel: String
    /// Whether the editor has the keyboard, for the chrome around it.
    var isFocused: Binding<Bool>?
    /// The 1-based line the caret is on, for a readout beside the text.
    var caretLine: Binding<Int>?

    var body: some View {
        CodeTextView(
            text: $text, isEditable: isEditable, isFocused: isFocused, caretLine: caretLine,
            accessibilityLabel: accessibilityLabel
        )
        .accessibilityLabel(accessibilityLabel)
    }

    /// The text to insert for a new line after `line`: a line break and the line's leading spaces.
    static func newline(after line: Substring) -> String {
        "\n" + line.prefix { $0 == " " }
    }

    /// Two spaces, YAML's usual step, in place of a tab.
    static let indent = "  "

    /// The lines `selection` touches, moved one step in or out. Outdenting takes up to two spaces off each.
    static func shifted(_ text: String, in selection: NSRange, inward: Bool) -> (text: String, range: NSRange) {
        let string = text as NSString
        let lines = string.lineRange(for: selection)
        // Split as NSString, by UTF-16 unit. A Swift string reads `\r\n` as one character, which `\n` never matches,
        // so a file with Windows line endings would shift as one line.
        let block = string.substring(with: lines) as NSString
        let endsWithNewline = block.hasSuffix("\n")
        var parts = block.components(separatedBy: "\n")
        if endsWithNewline { parts.removeLast() }
        let moved = parts.map { line -> String in
            if inward { return line.isEmpty || line == "\r" ? line : indent + line }
            let spaces = line.prefix { $0 == " " }.count
            return String(line.dropFirst(min(spaces, indent.count)))
        }
        let replacement = moved.joined(separator: "\n") + (endsWithNewline ? "\n" : "")
        let range = NSRange(location: lines.location, length: (replacement as NSString).length)
        return (string.replacingCharacters(in: lines, with: replacement), range)
    }

    /// The 1-based line that holds `location`.
    static func line(at location: Int, in text: String) -> Int {
        // By UTF-16 unit, like the location, so `\r\n` counts as the line break it is.
        text.utf16.prefix(location).reduce(1) { $0 + ($1 == 10 ? 1 : 0) }
    }

    /// The font the text is set in, which the placeholder shares so it sits where typing begins.
    static var font: Font { Font(platformFont as CTFont) }

    #if os(macOS)
    static var platformFont: NSFont {
        .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }
    #else
    /// Scales with Dynamic Type from a size that fits a compose line on an iPhone.
    static var platformFont: UIFont {
        UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedSystemFont(ofSize: 15, weight: .regular))
    }
    #endif

    /// A little air between lines. Code is read line by line, and a monospaced face sets them tight.
    static var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        return style
    }
}

#if os(macOS)
private struct CodeTextView: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool
    var isFocused: Binding<Bool>?
    var caretLine: Binding<Int>?
    var accessibilityLabel: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, isFocused: isFocused, caretLine: caretLine) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
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
        textView.usesFontPanel = false
        textView.font = CodeEditor.platformFont
        textView.textColor = .labelColor
        textView.insertionPointColor = NSColor(Color.ember)
        textView.defaultParagraphStyle = CodeEditor.paragraphStyle
        textView.typingAttributes = [
            .font: CodeEditor.platformFont, .foregroundColor: NSColor.labelColor,
            .paragraphStyle: CodeEditor.paragraphStyle,
        ]
        textView.textContainerInset = NSSize(width: 6, height: 10)
        textView.setAccessibilityLabel(accessibilityLabel)
        textView.string = text
        textView.isEditable = isEditable
        textView.isSelectable = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isFocused = isFocused
        context.coordinator.caretLine = caretLine
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
            context.coordinator.readCaret(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var isFocused: Binding<Bool>?
        var caretLine: Binding<Int>?

        init(text: Binding<String>, isFocused: Binding<Bool>?, caretLine: Binding<Int>?) {
            self.text = text
            self.isFocused = isFocused
            self.caretLine = caretLine
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            readCaret(textView)
        }

        func textDidBeginEditing(_ notification: Notification) {
            setFocused(true)
        }

        func textDidEndEditing(_ notification: Notification) {
            setFocused(false)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            readCaret(textView)
            // Clicking into the text makes it first responder without a `textDidBeginEditing`, which waits for a key.
            if textView.window?.firstResponder === textView { setFocused(true) }
        }

        func readCaret(_ textView: NSTextView) {
            guard let caretLine else { return }
            let line = CodeEditor.line(at: textView.selectedRange().location, in: textView.string)
            if caretLine.wrappedValue != line {
                DispatchQueue.main.async { caretLine.wrappedValue = line }
            }
        }

        private func setFocused(_ focused: Bool) {
            guard let isFocused, isFocused.wrappedValue != focused else { return }
            DispatchQueue.main.async { isFocused.wrappedValue = focused }
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertTab(_:)):
                textView.insertText(CodeEditor.indent, replacementRange: textView.selectedRange())
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                shift(textView, inward: false)
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
                setFocused(false)
                return true
            default:
                return false
            }
        }

        /// Moves the selected lines a step, through the text view so it stays one undo.
        private func shift(_ textView: NSTextView, inward: Bool) {
            let selection = textView.selectedRange()
            let lines = (textView.string as NSString).lineRange(for: selection)
            let shifted = CodeEditor.shifted(textView.string, in: selection, inward: inward)
            let replacement = (shifted.text as NSString).substring(with: shifted.range)
            guard textView.shouldChangeText(in: lines, replacementString: replacement) else { return }
            textView.replaceCharacters(in: lines, with: replacement)
            textView.didChangeText()
            textView.setSelectedRange(shifted.range)
        }
    }
}
#else
private struct CodeTextView: UIViewRepresentable {
    @Binding var text: String
    var isEditable: Bool
    var isFocused: Binding<Bool>?
    var caretLine: Binding<Int>?
    var accessibilityLabel: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, isFocused: isFocused, caretLine: caretLine) }

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
        // Inside a form, a short file must not catch the scroll meant for the form. A long one still scrolls.
        textView.alwaysBounceVertical = false
        textView.keyboardDismissMode = .interactive
        textView.font = CodeEditor.platformFont
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .label
        textView.tintColor = UIColor(Color.ember)
        textView.typingAttributes = [
            .font: CodeEditor.platformFont, .foregroundColor: UIColor.label,
            .paragraphStyle: CodeEditor.paragraphStyle,
        ]
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        textView.accessibilityLabel = accessibilityLabel
        textView.inputAccessoryView = context.coordinator.makeAccessory(for: textView)
        textView.text = text
        textView.isEditable = isEditable
        context.coordinator.spaceLines(textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isFocused = isFocused
        context.coordinator.caretLine = caretLine
        textView.isEditable = isEditable
        if textView.text != text {
            let selection = textView.selectedRange
            textView.text = text
            context.coordinator.spaceLines(textView)
            if selection.location <= (text as NSString).length {
                textView.selectedRange = selection
            }
            context.coordinator.readCaret(textView)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        var isFocused: Binding<Bool>?
        var caretLine: Binding<Int>?
        private weak var textView: UITextView?

        init(text: Binding<String>, isFocused: Binding<Bool>?, caretLine: Binding<Int>?) {
            self.text = text
            self.isFocused = isFocused
            self.caretLine = caretLine
        }

        /// Indent, outdent, and Done above the keyboard, which has no Tab of its own.
        func makeAccessory(for textView: UITextView) -> UIView {
            self.textView = textView
            let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
            toolbar.sizeToFit()
            let outdent = UIBarButtonItem(
                image: UIImage(systemName: "decrease.indent"), style: .plain, target: self,
                action: #selector(outdentLines))
            outdent.accessibilityLabel = "Outdent"
            let indent = UIBarButtonItem(
                image: UIImage(systemName: "increase.indent"), style: .plain, target: self,
                action: #selector(indentLines))
            indent.accessibilityLabel = "Indent"
            let done = UIBarButtonItem(
                title: "Done", style: .done, target: self, action: #selector(finishEditing))
            toolbar.items = [outdent, indent, .flexibleSpace(), done]
            toolbar.tintColor = UIColor(Color.ember)
            return toolbar
        }

        @objc private func indentLines() { shift(inward: true) }

        @objc private func outdentLines() { shift(inward: false) }

        @objc private func finishEditing() { textView?.resignFirstResponder() }

        /// Moves the selected lines a step, through the text input system so it stays one undo.
        private func shift(inward: Bool) {
            guard let textView else { return }
            let selection = textView.selectedRange
            let lines = (textView.text as NSString).lineRange(for: selection)
            let shifted = CodeEditor.shifted(textView.text, in: selection, inward: inward)
            let replacement = (shifted.text as NSString).substring(with: shifted.range)
            guard let start = textView.position(from: textView.beginningOfDocument, offset: lines.location),
                let end = textView.position(from: start, offset: lines.length),
                let textRange = textView.textRange(from: start, to: end)
            else { return }
            textView.replace(textRange, withText: replacement)
            textView.selectedRange = shifted.range
        }

        /// Sets the line spacing on text that arrived whole, which `text =` sets in the view's font alone.
        func spaceLines(_ textView: UITextView) {
            let range = NSRange(location: 0, length: textView.textStorage.length)
            guard range.length > 0 else { return }
            textView.textStorage.addAttribute(.paragraphStyle, value: CodeEditor.paragraphStyle, range: range)
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
            readCaret(textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            setFocused(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            setFocused(false)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            readCaret(textView)
        }

        func readCaret(_ textView: UITextView) {
            guard let caretLine else { return }
            let line = CodeEditor.line(at: textView.selectedRange.location, in: textView.text)
            if caretLine.wrappedValue != line {
                DispatchQueue.main.async { caretLine.wrappedValue = line }
            }
        }

        private func setFocused(_ focused: Bool) {
            guard let isFocused, isFocused.wrappedValue != focused else { return }
            DispatchQueue.main.async { isFocused.wrappedValue = focused }
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
    @Previewable @State var isFocused = false
    @Previewable @State var caretLine = 1
    VStack(alignment: .leading, spacing: 8) {
        CodeEditor(text: $text, accessibilityLabel: "Compose file", isFocused: $isFocused, caretLine: $caretLine)
            .frame(width: 520, height: 280)
            .well()
        Text("Line \(caretLine)\(isFocused ? ", editing" : "")")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .padding()
}
