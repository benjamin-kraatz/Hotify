import SwiftUI

/// Chips that narrow the preview board by state, each with its count and a flame that lights when it has previews.
struct PreviewFilterBar: View {
    var previews: [PreviewLine]
    @Binding var selection: PreviewFilter

    /// Inactive previews are rare, so their chip only shows when there are some.
    private var filters: [PreviewFilter] {
        PreviewFilter.allCases.filter { $0 != .inactive || count(of: $0) > 0 || selection == $0 }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(filters) { filter in
                chip(filter)
            }
        }
        .animation(.snappy, value: filters)
    }

    private func count(of filter: PreviewFilter) -> Int {
        previews.count(where: filter.includes)
    }

    private func chip(_ filter: PreviewFilter) -> some View {
        let count = count(of: filter)
        let isSelected = selection == filter
        return Button {
            selection = filter
        } label: {
            HStack(spacing: 6) {
                if filter == .all {
                    Image(systemName: "square.grid.2x2")
                        .imageScale(.small)
                } else {
                    // Lit only while the chip has previews, so an empty filter does not flicker.
                    FlameGlyph(heat: count > 0 ? filter.heat : .cold, height: 12, tone: .preview)
                }
                Text(filter.title)
                Text(count, format: .number)
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? AnyShapeStyle(.pilot.opacity(0.8)) : AnyShapeStyle(.secondary))
                    .contentTransition(.numericText())
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isSelected ? AnyShapeStyle(.pilot) : AnyShapeStyle(.primary))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                isSelected ? AnyShapeStyle(.pilot.opacity(0.15)) : AnyShapeStyle(.primary.opacity(0.05)), in: .capsule
            )
            .overlay {
                Capsule()
                    .strokeBorder(.pilot.opacity(isSelected ? 0.45 : 0), lineWidth: 1)
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(count == 0 && filter != .all && !isSelected)
        .opacity(count == 0 && filter != .all && !isSelected ? 0.55 : 1)
        .animation(.snappy(duration: 0.2), value: isSelected)
        .accessibilityLabel("\(filter.title), \(count)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    @Previewable @State var selection = PreviewFilter.all
    PreviewFilterBar(
        previews: [
            PreviewLine(number: 42, deployments: [DeploymentLine(id: "a", status: "finished", pullRequest: 42)]),
            PreviewLine(number: 41, deployments: [DeploymentLine(id: "b", status: "in_progress", pullRequest: 41)]),
        ],
        selection: $selection
    )
    .padding()
}
