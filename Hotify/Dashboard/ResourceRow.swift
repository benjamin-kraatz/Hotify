import SwiftUI

/// One application, database, or service, with start, restart, and stop.
struct ResourceRow: View {
    var title: String
    var status: String
    var detailLines: [String]
    var isBusy: Bool
    var onStart: () -> Void
    var onRestart: () -> Void
    var onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            Text(status)
            ForEach(detailLines, id: \.self) { line in
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
    ResourceRow(
        title: "convex",
        status: "running:healthy",
        detailLines: [
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
