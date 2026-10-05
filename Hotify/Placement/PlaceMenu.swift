import SwiftUI

/// Which place sheet is open: move to an environment, clone, or migrate to another server.
enum PlacementIntent: Hashable, Identifiable {
    case move
    case clone
    case migrate

    var id: Self { self }
}

/// The resource toolbar's Place menu. Each item opens its own sheet.
struct PlaceMenu: View {
    var isEnabled: Bool
    var onChoose: (PlacementIntent) -> Void

    var body: some View {
        Menu {
            Button("Move…", systemImage: "arrow.right.square") { onChoose(.move) }
            Button("Clone…", systemImage: "plus.square.on.square") { onChoose(.clone) }
            Button("Migrate…", systemImage: "arrow.triangle.swap") { onChoose(.migrate) }
        } label: {
            Label("Place", systemImage: "arrow.left.arrow.right")
        }
        .menuIndicator(.hidden)
        .help("Move to another environment, clone, or migrate to another server")
        .disabled(!isEnabled)
    }
}

#Preview {
    PlaceMenu(isEnabled: true) { _ in }
        .padding()
}
