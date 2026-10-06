import SwiftUI

/// The head of a move, clone, or migrate sheet: the resource where it is now, an arrow, and where it goes. The far
/// end changes as you pick, so you can read the result before you confirm it.
struct PlacementJourney: View {
    var resourceName: String
    var heat: Heat
    /// Where the resource is now, such as `Website · production`. `nil` leaves the line out.
    var origin: String?
    var destination: String
    /// What the destination is, such as `Environment` or `Server`.
    var destinationKind: String
    var destinationImage: String
    /// The arrow's symbol. Clone shows a copy, the others a move.
    var arrowImage = "arrow.right"
    /// A place color for the destination, when it is an environment.
    var destinationTint: PlaceTint?

    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            end(alignment: .leading) {
                HStack(spacing: 8) {
                    FlameGlyph(heat: heat, height: 18)
                    Text(resourceName)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let origin {
                    Text(origin)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Image(systemName: arrowImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.ember)
                .frame(width: 30, height: 30)
                .background(.ember.opacity(0.12), in: .circle)
                .symbolEffect(.bounce, value: reduceMotion ? "" : destination)
                .accessibilityHidden(true)

            end(alignment: .trailing) {
                HStack(spacing: 6) {
                    if let destinationTint {
                        PlaceMark(tint: destinationTint)
                    } else {
                        Image(systemName: destinationImage)
                            .foregroundStyle(.secondary)
                    }
                    Text(destination)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .contentTransition(.interpolate)
                }
                Text(destinationKind)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .well()
        .animation(reduceMotion ? nil : .snappy, value: destination)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(resourceName) to \(destination)")
    }

    private func end<Content: View>(alignment: HorizontalAlignment, @ViewBuilder content: () -> Content)
        -> some View
    {
        VStack(alignment: alignment, spacing: 3, content: content)
            .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }
}

#Preview {
    VStack(spacing: 16) {
        PlacementJourney(
            resourceName: "marketing-site", heat: .lit, origin: "Website · production", destination: "staging",
            destinationKind: "Environment", destinationImage: "square.3.layers.3d", destinationTint: .indigo)
        PlacementJourney(
            resourceName: "postgres", heat: .cold, origin: nil, destination: "edge-01 · apps",
            destinationKind: "Server", destinationImage: "server.rack", arrowImage: "plus.square.on.square")
    }
    .padding()
    .frame(width: 480)
}
