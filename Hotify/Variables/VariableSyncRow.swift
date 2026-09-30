import CoolifyAPI
import SwiftUI

/// One key in a comparison: what the destination holds now, what the source would put there, and what happens to it.
struct VariableSyncRow: View {
    var change: VariableSyncChange
    /// Whether the row is picked for copying. `nil` for a row that offers no choice.
    var isSelected: Bool?
    /// The destination gives up the keys the source lacks.
    var deleting: Bool

    private var isGoing: Bool {
        change.kind == .destinationOnly && deleting
    }

    private var verb: String? {
        switch change.kind {
        case .create: "Create"
        case .update: "Overwrite"
        case .destinationOnly: deleting ? "Delete" : "Keep"
        case .unchanged, .unavailable: nil
        }
    }

    private var sourceTags: [String] {
        change.source.map { VariableLine(variable: $0).tags } ?? []
    }

    private var destinationTags: [String] {
        change.destination.map { VariableLine(variable: $0).tags } ?? []
    }

    /// The comment that ends up on the destination.
    private var comment: String? {
        let comment = (change.source ?? change.destination)?.comment?.trimmingCharacters(in: .whitespacesAndNewlines)
        return comment.flatMap { $0.isEmpty ? nil : $0 }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let isSelected {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.ember) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(change.key)
                        .font(.callout.monospaced().weight(.semibold))
                        .strikethrough(isGoing)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(1)
                    ForEach(change.source == nil ? destinationTags : sourceTags, id: \.self) { tag in
                        Tag(text: tag)
                    }
                    Spacer(minLength: 8)
                    if let verb {
                        Text(verb)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isGoing ? AnyShapeStyle(.glow) : AnyShapeStyle(.secondary))
                            .contentTransition(.interpolate)
                    }
                }

                values
                    .font(.callout.monospaced())
                    // Cut in the middle, so a URL or token keeps both ends.
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .privacySensitive()

                if change.kind == .update, sourceTags != destinationTags {
                    Text("Options change from \(Self.list(destinationTags)) to \(Self.list(sourceTags)).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let comment {
                    Text(comment)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(.rect)
        .animation(.snappy, value: isSelected)
        .animation(.snappy, value: deleting)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected == true ? .isSelected : [])
    }

    @ViewBuilder
    private var values: some View {
        switch change.kind {
        case .create, .unchanged:
            value(change.source?.value)
                .foregroundStyle(change.kind == .create ? .secondary : .tertiary)
        case .update:
            if change.source?.value == change.destination?.value {
                // Only an option or the comment differs.
                value(change.source?.value)
                    .foregroundStyle(.tertiary)
            } else {
                value(change.destination?.value)
                    .strikethrough()
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Now \(change.destination?.value ?? "withheld")")
                Label {
                    value(change.source?.value)
                } icon: {
                    Image(systemName: "arrow.turn.down.right")
                }
                .foregroundStyle(.secondary)
            }
        case .destinationOnly:
            value(change.destination?.value)
                .strikethrough(isGoing)
                .foregroundStyle(.tertiary)
        case .unavailable:
            Label("Coolify withholds this value", systemImage: "eye.slash")
                .foregroundStyle(.tertiary)
        }
    }

    private func value(_ value: String?) -> Text {
        guard let value else { return Text("Withheld by Coolify") }
        return Text(value.isEmpty ? "Empty" : value)
    }

    private static func list(_ tags: [String]) -> String {
        tags.isEmpty ? "none" : tags.joined(separator: ", ")
    }
}

#Preview {
    let source = try! JSONDecoder().decode(
        [EnvironmentVariable].self,
        from: Data(
            """
            [
                {"uuid": "1", "key": "API_URL", "value": "https://api.example.com", "isLiteral": true},
                {"uuid": "2", "key": "FEATURE_FLAGS", "value": "pricing,checkout", "comment": "Read at boot"},
                {"uuid": "3", "key": "NODE_ENV", "value": "production"},
                {"uuid": "4", "key": "STRIPE_SECRET_KEY", "isShownOnce": true}
            ]
            """.utf8))
    let destination = try! JSONDecoder().decode(
        [EnvironmentVariable].self,
        from: Data(
            """
            [
                {"uuid": "5", "key": "API_URL", "value": "https://staging.api.example.com"},
                {"uuid": "6", "key": "NODE_ENV", "value": "production"},
                {"uuid": "7", "key": "LEGACY_TOKEN", "value": "abc123"}
            ]
            """.utf8))
    let plan = try! VariableSyncPlan(
        source: source, destination: destination, sourcePreview: false, destinationPreview: false,
        destinationIsApplication: true)
    VStack(spacing: 0) {
        ForEach(plan.changes) { change in
            VariableSyncRow(
                change: change,
                isSelected: change.kind == .create || change.kind == .update ? change.kind == .update : nil,
                deleting: true
            )
            Divider()
        }
    }
    .well()
    .frame(width: 520)
    .padding()
}
