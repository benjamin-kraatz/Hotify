import CoolifyAPI
import SwiftUI

/// A compose file being written or changed: the text, the containers Hotify reads in it, and what looks wrong.
///
/// The text is kept exactly as typed. The outline and the check only read it, so YAML they do not follow is never
/// rewritten, and only an empty file is held back. Coolify judges the rest when it is saved.
struct ComposeEditor: View {
    @Binding var compose: String
    var isEditable = true
    /// The editor's height inside a form. `nil` lets it fill what it is given, as on a screen of its own.
    var height: CGFloat?

    @State private var isFocused = false
    @State private var caretLine = 1
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let placeholder = """
        services:
          web:
            image: nginx:1.27
            environment:
              - SERVICE_URL_WEB_80
        """

    private static let cornerRadius: CGFloat = 12

    var body: some View {
        let outline = ComposeOutline(compose)
        // Nothing to say about a file not started yet. The placeholder shows what goes there.
        let findings = compose.isEmpty ? [] : ComposeCheck(compose).findings

        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 0) {
                CodeEditor(
                    text: $compose, isEditable: isEditable, accessibilityLabel: "Compose file",
                    isFocused: $isFocused, caretLine: $caretLine
                )
                .frame(height: height)
                .frame(minHeight: 160, maxHeight: height == nil ? .infinity : nil)
                .overlay(alignment: .topLeading) { placeholder }
                .overlay(alignment: .topTrailing) { pasteButton }
                Divider()
                ComposeSummary(
                    outline: outline, lineCount: lineCount, caretLine: isFocused ? caretLine : nil,
                    isBlocking: findings.contains { $0.severity == .blocking })
            }
            .well(cornerRadius: Self.cornerRadius)
            .overlay {
                // Lit like the gallery's search field while the keyboard is here.
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .strokeBorder(
                        isFocused ? AnyShapeStyle(.ember.opacity(0.5)) : AnyShapeStyle(.primary.opacity(0.08)),
                        lineWidth: 1)
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: isFocused)

            ForEach(findings) { finding in
                FindingRow(finding: finding)
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: findings)
    }

    @ViewBuilder
    private var placeholder: some View {
        if compose.isEmpty {
            Text(verbatim: Self.placeholder)
                .font(CodeEditor.font)
                .foregroundStyle(.tertiary)
                .padding(.top, Self.placeholderInsets.top)
                .padding(.leading, Self.placeholderInsets.leading)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .transition(.opacity)
        }
    }

    /// The quickest start: a file copied from somewhere else, in one tap.
    @ViewBuilder
    private var pasteButton: some View {
        if compose.isEmpty, isEditable {
            PasteButton(payloadType: String.self) { strings in
                guard let text = strings.first else { return }
                Task { @MainActor in compose = text }
            }
            .labelStyle(.titleAndIcon)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .padding(10)
            .transition(.opacity)
            .help("Paste a compose file from the clipboard")
        }
    }

    private var lineCount: Int {
        compose.isEmpty ? 0 : compose.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
    }

    /// Where the text view starts its first line, so the placeholder sits where typing begins.
    private static var placeholderInsets: EdgeInsets {
        #if os(macOS)
        EdgeInsets(top: 10, leading: 11, bottom: 0, trailing: 0)
        #else
        EdgeInsets(top: 12, leading: 13, bottom: 0, trailing: 0)
        #endif
    }
}

/// The containers Hotify reads in the file, how long it is, and where the caret is while it is being edited.
private struct ComposeSummary: View {
    var outline: ComposeOutline
    var lineCount: Int
    /// `nil` while the editor is not being typed in.
    var caretLine: Int?
    /// Whether the file cannot be saved as it is, which colors the count.
    var isBlocking: Bool

    var body: some View {
        HStack(spacing: 12) {
            if outline.containers.isEmpty {
                Label {
                    Text(lineCount == 0 ? "Waiting for a compose file" : "No containers read yet")
                } icon: {
                    Image(systemName: ComposeMark.systemImage)
                }
                .foregroundStyle(isBlocking ? AnyShapeStyle(.glow) : AnyShapeStyle(.tertiary))
            } else {
                Label {
                    Text(outline.containers.map(\.name).joined(separator: ", "))
                        .lineLimit(1)
                        .truncationMode(.tail)
                } icon: {
                    Image(systemName: ComposeMark.systemImage)
                        .foregroundStyle(.ember)
                }
                .accessibilityLabel(
                    "\(outline.containers.count) containers: \(ListFormatter.localizedString(byJoining: outline.containers.map(\.name)))"
                )
            }
            Spacer(minLength: 8)
            Text(position)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .fixedSize()
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var position: String {
        let lines = lineCount == 1 ? "1 line" : "\(lineCount) lines"
        guard let caretLine, lineCount > 0 else { return lines }
        return "Line \(caretLine) of \(lineCount)"
    }
}

/// One thing the check found. Amber holds a save back, grey is only advice.
private struct FindingRow: View {
    var finding: ComposeCheck.Finding

    private var isBlocking: Bool { finding.severity == .blocking }

    var body: some View {
        Label {
            Text(finding.message)
                .foregroundStyle(isBlocking ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: isBlocking ? "exclamationmark.triangle.fill" : "lightbulb")
                .foregroundStyle(isBlocking ? AnyShapeStyle(.glow) : AnyShapeStyle(.secondary))
        }
        .font(.callout)
        .padding(.horizontal, 4)
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isBlocking ? "Holds the save: \(finding.message)" : "Advice: \(finding.message)")
    }
}

#Preview("Written") {
    @Previewable @State var compose = """
        services:
          web:
            image: nginx:1.27
            environment:
              - SERVICE_URL_WEB_80
          worker:
            build: .
        """
    Form {
        Section("Compose File") {
            ComposeEditor(compose: $compose, height: 260)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
    }
    .formStyle(.grouped)
    .frame(width: 560, height: 480)
}

#Preview("Empty") {
    @Previewable @State var compose = ""
    ComposeEditor(compose: $compose)
        .padding()
        .frame(width: 520, height: 360)
}

#Preview("Read only") {
    @Previewable @State var compose = "services:\n  cache:\n    image: redis:7\n"
    ComposeEditor(compose: $compose, isEditable: false)
        .padding()
        .frame(width: 520, height: 300)
}
