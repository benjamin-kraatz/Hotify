import CoolifyAPI
import SwiftUI

/// The server's Docker cleanup schedule, what a run deletes, and the runs Coolify has recorded.
struct DockerCleanupSection: View {
    var model: ServerPageModel
    var canAct: Bool
    var onSave: () -> Void
    var onRun: () -> Void

    var body: some View {
        Section {
            TextField("Frequency", text: frequency, prompt: Text("0 2 * * * or daily"))
                .autocorrectionDisabled()
            HStack {
                Text("Disk threshold")
                Spacer(minLength: 8)
                TextField("80", text: threshold)
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                .keyboardType(.numberPad)
                    #endif
                    .frame(width: 64)
                    .monospacedDigit()
                Text("%")
                    .foregroundStyle(.secondary)
            }
            Toggle("Force cleanup", isOn: flag(\.forceDockerCleanup))
            Toggle("Delete unused volumes", isOn: flag(\.deleteUnusedVolumes))
            Toggle("Delete unused networks", isOn: flag(\.deleteUnusedNetworks))
            Toggle("Don't keep old application images", isOn: flag(\.disableApplicationImageRetention))
            HStack(spacing: 10) {
                Button(action: onSave) {
                    Label(model.write == .saveCleanup ? "Saving…" : "Save", systemImage: "checkmark")
                }
                .glassButton(prominent: model.hasCleanupChanges)
                .disabled(!canAct || !model.hasCleanupChanges || model.isBusy)
                Button(action: onRun) {
                    Label(model.write == .runCleanup ? "Cleaning…" : "Clean Up Now", systemImage: "eraser")
                }
                .glassButton()
                .disabled(!canAct || model.isBusy)
            }
        } header: {
            Text("Docker cleanup")
        } footer: {
            Text(
                "Coolify prunes unused Docker data on this schedule. "
                    + "The disk threshold is a percent from 1 to 99. "
                    + "Turning off image retention drops old images Coolify kept for rollback."
            )
        }

        Section("Recent runs") {
            if model.executions.isEmpty {
                Text("No cleanup runs yet.")
                    .foregroundStyle(.secondary)
            } else {
                if model.executions.count > 1 {
                    RunStrip(heats: model.executions.map(\.heat), verb: "finished")
                }
                ForEach(model.executions) { execution in
                    CleanupRunRow(execution: execution)
                }
            }
        }
    }

    private var frequency: Binding<String> {
        Binding(
            get: { model.draft?.dockerCleanupFrequency ?? "" },
            set: { model.draft?.dockerCleanupFrequency = $0.isEmpty ? nil : $0 }
        )
    }

    private var threshold: Binding<String> {
        Binding(
            get: { model.draft?.dockerCleanupThreshold.map(String.init) ?? "" },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)
                guard let value = Int(digits) else {
                    model.draft?.dockerCleanupThreshold = nil
                    return
                }
                model.draft?.dockerCleanupThreshold = min(max(value, 1), 99)
            }
        )
    }

    private func flag(_ key: WritableKeyPath<DockerCleanupSettings, Bool?>) -> Binding<Bool> {
        Binding(
            get: { model.draft?[keyPath: key] ?? false },
            set: { model.draft?[keyPath: key] = $0 }
        )
    }
}

extension DockerCleanupExecution {
    /// A finished prune is lit, a failed one needs a look, and one queued or running is warming.
    var heat: Heat {
        switch status.lowercased() {
        case "success", "finished", "completed": .lit
        case "failed", "error": .troubled
        case "queued", "running", "in_progress", "started": .warming
        default: .unknown
        }
    }
}

/// One Docker cleanup run: how it ended, and when.
private struct CleanupRunRow: View {
    var execution: DockerCleanupExecution

    private var heat: Heat { execution.heat }

    private var status: String {
        switch execution.status.lowercased() {
        case "success", "finished", "completed": "Finished"
        case "failed", "error": "Failed"
        case "queued": "Queued"
        case "running", "in_progress", "started": "Running…"
        default:
            execution.status.isEmpty
                ? "Unknown" : execution.status.prefix(1).uppercased() + execution.status.dropFirst()
        }
    }

    private var message: String? {
        guard let message = execution.message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty else {
            return nil
        }
        return message
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            FlameGlyph(heat: heat, height: 16)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(status)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(heat.needsAttention ? AnyShapeStyle(.glow) : AnyShapeStyle(.primary))
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(heat == .troubled ? AnyShapeStyle(.glow) : AnyShapeStyle(.secondary))
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 8)
            if let date = execution.finishedAtDate ?? execution.createdAtDate {
                Text(date, format: .relative(presentation: .named))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .help(date.formatted(date: .abbreviated, time: .standard))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        Form {
            DockerCleanupSection(model: .sample, canAct: true, onSave: {}, onRun: {})
        }
    }
    .frame(width: 560, height: 520)
}
