import CoolifyAPI
import SwiftUI

/// Names the database a restore writes into: its name, engine, service, and instance, with its flame.
struct RestoreTargetSection: View {
    var target: RestoreTarget
    var instanceName: String?

    private var detail: String {
        var parts = [target.engineName]
        if let service = target.serviceName, !service.isEmpty {
            parts.append("in \(service)")
        }
        if let instanceName, !instanceName.isEmpty {
            parts.append("on \(instanceName)")
        }
        return parts.joined(separator: " ")
    }

    var body: some View {
        Section {
            HStack(spacing: 12) {
                FlameGlyph(heat: Heat(status: target.status), height: 26)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.name)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Text(StatusLabel.text(for: target.status))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } header: {
            Text("Restore Into")
        }
    }
}

#Preview {
    Form {
        RestoreTargetSection(
            target: RestoreTarget(
                importTarget: .serviceDatabase(service: "svc-1", database: "db-1"),
                name: "postgres",
                engine: .postgresql,
                serviceName: "Convex",
                status: "running:healthy"
            ),
            instanceName: "Home lab"
        )
    }
    .formStyle(.grouped)
    .frame(width: 480, height: 200)
}
