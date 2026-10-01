import SwiftUI

/// The dot beside a project's or environment's name that shows its color. Nothing when it has none.
///
/// A symbol rather than a shape, so it sits on the text's baseline and scales with the font around it.
struct PlaceMark: View {
    var tint: PlaceTint?

    var body: some View {
        if let tint {
            Image(systemName: "circle.fill")
                .imageScale(.small)
                .foregroundStyle(tint.color)
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            PlaceMark(tint: .teal)
            Text("Website").font(.headline)
        }
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            PlaceMark(tint: .orange)
            Text("production").font(.subheadline.weight(.semibold))
        }
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            PlaceMark(tint: nil)
            Text("No color").font(.subheadline)
        }
    }
    .padding()
}
