import SwiftUI

/// Start, restart, and stop, offered by what makes sense for the resource's heat.
struct ResourceActionButtons: View {
    var heat: Heat
    var isBusy: Bool
    var onAction: (ResourceAction) -> Void

    var body: some View {
        if heat == .cold || heat == .unknown {
            button(.start)
        }
        if heat != .cold {
            button(.restart)
            button(.stop)
        }
    }

    private func button(_ action: ResourceAction) -> some View {
        Button(action == .stop ? "Stop…" : action.title, systemImage: action.systemImage) {
            onAction(action)
        }
        .disabled(isBusy)
    }
}
