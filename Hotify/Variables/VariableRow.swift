import SwiftUI

/// One variable: its key, then its value once unlocked. Masked values never hint at their length.
struct VariableRow: View {
    var line: VariableLine
    var isOpen: Bool
    var onCopy: (String) -> Void

    @State private var copies = 0

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(line.key)
                        .font(.callout.monospaced().weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(1)
                    ForEach(line.tags, id: \.self) { tag in
                        VariableTag(text: tag)
                    }
                }
                valueText
                if let comment = line.comment {
                    Text(comment)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isOpen, let value = line.value {
                Button {
                    onCopy(value)
                    copies += 1
                } label: {
                    Label("Copy value", systemImage: copies > 0 ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Copy the value of \(line.key)")
                .transition(.opacity)
                .task(id: copies) {
                    guard copies > 0 else { return }
                    try? await Task.sleep(for: .seconds(1.5))
                    copies = 0
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var valueText: some View {
        Group {
            if !isOpen {
                Text(verbatim: "••••••••••")
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Value locked")
            } else if let value = line.value {
                VStack(alignment: .leading, spacing: 2) {
                    Text(value.isEmpty ? "Empty" : value)
                        .foregroundStyle(value.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                        // One line, cut in the middle, so a URL or token keeps both ends and never hyphenates.
                        .lineLimit(line.isMultiline ? 3 : 1)
                        .truncationMode(line.isMultiline ? .tail : .middle)
                    if let resolved = line.resolvedValue {
                        Label(resolved, systemImage: "arrow.turn.down.right")
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help("What the shared reference resolves to")
                    }
                }
                .privacySensitive()
                .transition(.blurReplace)
            } else {
                Label(
                    line.isShownOnce ? "Hidden by Coolify after saving" : "Not readable with this API token",
                    systemImage: "eye.slash"
                )
                .foregroundStyle(.tertiary)
            }
        }
        .font(.callout.monospaced())
    }
}

/// A small capsule for facts like `Literal`.
struct VariableTag: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(0.7), in: .capsule)
            .fixedSize()
    }
}

#Preview {
    let lines = [
        VariableLine(id: "1", key: "DATABASE_URL", value: "postgres://app:secret@db:5432/app", isLiteral: true),
        VariableLine(
            id: "2",
            key: "API_URL",
            value: "{{project.API_URL}}",
            resolvedValue: "https://api.example.com",
            comment: "Shared with the worker"
        ),
        VariableLine(id: "3", key: "STRIPE_SECRET_KEY", isShownOnce: true),
        VariableLine(id: "4", key: "NODE_ENV", value: "production", isRuntime: false, isBuildtime: true),
    ]
    VStack(spacing: 0) {
        ForEach(lines) { line in
            VariableRow(line: line, isOpen: true, onCopy: { _ in })
            Divider()
        }
        VariableRow(line: lines[0], isOpen: false, onCopy: { _ in })
    }
    .frame(width: 480)
    .padding()
}
