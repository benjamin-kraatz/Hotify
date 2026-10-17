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

    private static let placeholder = """
        services:
          web:
            image: nginx:1.27
            environment:
              - SERVICE_URL_WEB_80
        """

    var body: some View {
        let outline = ComposeOutline(compose)
        // Nothing to say about a file not started yet. The placeholder shows what goes there.
        let findings = compose.isEmpty ? [] : ComposeCheck(compose).findings

        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 0) {
                CodeEditor(text: $compose, isEditable: isEditable, accessibilityLabel: "Compose file")
                    .frame(height: height)
                    .frame(minHeight: 160)
                    .overlay(alignment: .topLeading) {
                        if compose.isEmpty {
                            Text(verbatim: Self.placeholder)
                                .font(.body.monospaced())
                                .foregroundStyle(.tertiary)
                                .padding(.top, Self.placeholderInsets.top)
                                .padding(.leading, Self.placeholderInsets.leading)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                Divider()
                ComposeSummary(outline: outline, lineCount: lineCount)
            }
            .well(cornerRadius: 12)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
            }

            ForEach(findings) { finding in
                FindingRow(finding: finding)
            }
        }
        .animation(.snappy, value: findings)
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

/// The containers Hotify reads in the file, and how long it is.
private struct ComposeSummary: View {
    var outline: ComposeOutline
    var lineCount: Int

    var body: some View {
        HStack(spacing: 12) {
            if outline.containers.isEmpty {
                Text("No containers read yet")
                    .foregroundStyle(.tertiary)
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
            Text(lineCount == 1 ? "1 line" : "\(lineCount) lines")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
        .transition(.opacity)
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
