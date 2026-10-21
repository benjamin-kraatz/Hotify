import CoolifyAPI
import SwiftUI

/// States, for the chosen engine and options, what the restore drops or replaces and whether a failure rolls back.
struct RestoreConsequenceSection: View {
    var consequences: RestoreConsequences

    var body: some View {
        Section {
            ForEach(Array(consequences.lines.enumerated()), id: \.offset) { index, line in
                Label {
                    Text(line)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: index == 0 && consequences.replacesData ? "arrow.triangle.swap" : "info.circle")
                        .foregroundStyle(
                            index == 0 && consequences.replacesData ? AnyShapeStyle(.glow) : AnyShapeStyle(.secondary))
                }
                .font(.callout)
            }
        } header: {
            Text("What Happens to the Current Data")
        }
    }
}

#Preview {
    Form {
        RestoreConsequenceSection(
            consequences: RestoreConsequences(
                engine: .postgresql, options: .init(replaceExisting: true), format: .unknown))
        RestoreConsequenceSection(
            consequences: RestoreConsequences(
                engine: .mysql, options: .init(dumpAll: true, restoreMySQLUsers: true), format: .sql))
    }
    .formStyle(.grouped)
    .frame(width: 480, height: 520)
}
