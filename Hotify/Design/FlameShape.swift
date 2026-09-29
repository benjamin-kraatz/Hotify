import SwiftUI

/// The teardrop from the Hotify logo: a sharp tip on top, a round belly below.
///
/// Draw it in a frame about 1.5 times taller than it is wide to match the logo.
nonisolated struct FlameShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = rect.width / 2
        let belly = rect.maxY - radius
        let tip = CGPoint(x: rect.midX, y: rect.minY)
        // Bézier handle length that bends a cubic curve into a quarter circle.
        let handle = radius * 0.5523

        var path = Path()
        path.move(to: tip)
        path.addCurve(
            to: CGPoint(x: rect.minX, y: belly),
            control1: CGPoint(x: rect.midX - rect.width * 0.12, y: rect.minY + rect.height * 0.2),
            control2: CGPoint(x: rect.minX, y: belly - radius * 0.85)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: rect.minX, y: belly + handle),
            control2: CGPoint(x: rect.midX - handle, y: rect.maxY)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: belly),
            control1: CGPoint(x: rect.midX + handle, y: rect.maxY),
            control2: CGPoint(x: rect.maxX, y: belly + handle)
        )
        path.addCurve(
            to: tip,
            control1: CGPoint(x: rect.maxX, y: belly - radius * 0.85),
            control2: CGPoint(x: rect.midX + rect.width * 0.12, y: rect.minY + rect.height * 0.2)
        )
        path.closeSubpath()
        return path
    }
}

#Preview {
    FlameShape()
        .fill(.ember)
        .frame(width: 120, height: 180)
        .padding()
}
