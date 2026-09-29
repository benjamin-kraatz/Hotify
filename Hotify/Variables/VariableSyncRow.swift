import CoolifyAPI
import SwiftUI

/// One comparison entry with both values and the flags that will be transferred.
struct VariableSyncRow: View {
    var change: VariableSyncChange
    var deleting: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(change.key).font(.body.monospaced().weight(.semibold))
                Spacer()
                Text(label).font(.caption).foregroundStyle(deleting || change.kind == .unavailable ? .glow : .secondary)
            }
            if let source = change.source {
                Text("Source: \(source.value ?? "Value withheld by Coolify")").font(.caption.monospaced())
                    .textSelection(.enabled)
                Text("Flags: \(flags(source))").font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let comment = change.source?.comment, !comment.isEmpty {
                Text("Source comment: \(comment)").font(.caption)
            }
            if let comment = change.destination?.comment, !comment.isEmpty {
                Text("Destination comment: \(comment)").font(.caption)
            }
            if let target = change.destination {
                Text("Destination: \(target.value ?? "Value withheld by Coolify")").font(.caption.monospaced())
                    .textSelection(.enabled)
                Text("Flags: \(flags(target))").font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    private func flags(_ variable: EnvironmentVariable) -> String {
        var tags = VariableLine(variable: variable).tags
        if variable.isRuntime == true && variable.isBuildtime == true { tags.insert("Build and runtime", at: 0) }
        return tags.isEmpty ? "Default" : tags.joined(separator: ", ")
    }

    private var label: String {
        switch change.kind {
        case .create: "Create"
        case .update: "Overwrite"
        case .unchanged: "Same"
        case .unavailable: "Cannot copy"
        case .destinationOnly: deleting ? "Delete" : "Keep"
        }
    }
}

#Preview {
    let source = try! JSONDecoder().decode(
        [EnvironmentVariable].self, from: Data(#"[{"uuid":"v","key":"API_URL","value":"https://example.com"}]"#.utf8))
    let plan = try! VariableSyncPlan(
        source: source, destination: [], sourcePreview: false, destinationPreview: false, destinationIsApplication: true
    )
    VariableSyncRow(change: plan.changes[0], deleting: false).padding()
}
