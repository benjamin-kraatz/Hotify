import SwiftUI

/// One service and the containers Coolify reports under it.
struct ServiceRow: View {
    var title: String
    var status: String
    var containerLines: [String]
    var isBusy: Bool
    var onStart: () -> Void
    var onRestart: () -> Void
    var onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            Text(status)
            ForEach(containerLines, id: \.self) { line in
                Text(line)
            }
            HStack {
                Button("Start", action: onStart)
                Button("Restart", action: onRestart)
                Button("Stop", action: onStop)
            }
            .disabled(isBusy)
        }
    }
}

#Preview {
    ServiceRow(
        title: "convex",
        status: "running:healthy",
        containerLines: [
            "dashboard running:healthy",
            "backend running:healthy",
        ],
        isBusy: false,
        onStart: {},
        onRestart: {},
        onStop: {}
    )
    .padding()
}
