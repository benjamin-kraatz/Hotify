import SwiftUI

/// Picks the color of a project or an environment, or none, from swatches that wrap on a narrow screen.
struct PlaceTintPicker: View {
    @Binding var selection: PlaceTint?

    @ScaledMetric private var swatch: CGFloat = 22

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: swatch + 6, maximum: swatch + 6), spacing: 6)],
            alignment: .leading,
            spacing: 6
        ) {
            button(for: nil)
            ForEach(PlaceTint.allCases) { tint in
                button(for: tint)
            }
        }
        .animation(.snappy(duration: 0.2), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Color")
    }

    private func button(for tint: PlaceTint?) -> some View {
        let isSelected = selection == tint
        let title = tint?.title ?? "No Color"
        return Button {
            selection = tint
        } label: {
            swatchFace(tint)
                .frame(width: swatch, height: swatch)
                .padding(3)
                .overlay {
                    Circle()
                        .strokeBorder(
                            tint.map { AnyShapeStyle($0.color) } ?? AnyShapeStyle(.secondary),
                            lineWidth: 2
                        )
                        .opacity(isSelected ? 1 : 0)
                }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func swatchFace(_ tint: PlaceTint?) -> some View {
        if let tint {
            Circle()
                .fill(tint.color)
        } else {
            Circle()
                .strokeBorder(.secondary.opacity(0.6), lineWidth: 1.5)
                .overlay {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
        }
    }
}

#Preview {
    @Previewable @State var selection: PlaceTint? = .teal
    VStack(alignment: .leading, spacing: 20) {
        PlaceTintPicker(selection: $selection)
        Text(selection?.title ?? "No color")
            .foregroundStyle(.secondary)
    }
    .padding()
    .frame(width: 300)
}
