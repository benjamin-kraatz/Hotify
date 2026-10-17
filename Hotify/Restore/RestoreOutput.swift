import CoolifyAPI
import SwiftUI

/// Coolify's output for an import, or why there is none to show.
struct RestoreOutput: View {
    /// `nil` when Coolify left it out, which it does for a token that may not read sensitive data.
    var output: String?
    var isFinished: Bool

    private var text: String? {
        guard let output = output?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty else { return nil }
        return output
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output")
                .font(.headline)
            if let text {
                ScrollView {
                    Text(text)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .defaultScrollAnchor(.bottom)
                .frame(minHeight: 120, maxHeight: 280)
                .well()
            } else {
                Text(placeholder)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var placeholder: String {
        if output == nil {
            return "Coolify only sends an import's output to a token that may read sensitive data. "
                + "Its status still shows here."
        }
        return isFinished ? "Coolify sent no output." : "No output yet."
    }
}

#Preview {
    VStack(spacing: 24) {
        RestoreOutput(
            output: "Restoring app.dmp into app…\npg_restore: creating TABLE public.users\nDone.", isFinished: true)
        RestoreOutput(output: nil, isFinished: false)
    }
    .padding(20)
    .frame(width: 480)
}
