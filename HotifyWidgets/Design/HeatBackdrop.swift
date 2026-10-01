import SwiftUI

/// A widget's background: the system surface with a low glow of whatever burns hottest on it.
///
/// Running warms the bottom edge red, anything that wants a look warms it amber, and a cold widget stays plain.
struct HeatBackdrop: View {
    var heats: [Heat]

    private var glow: Color? {
        if heats.contains(where: \.needsAttention) { return .glow }
        if heats.contains(.lit) { return .ember }
        return nil
    }

    var body: some View {
        ZStack {
            Rectangle().fill(.background)
            if let glow {
                RadialGradient(
                    colors: [glow.opacity(0.22), glow.opacity(0)],
                    center: .bottomLeading,
                    startRadius: 0,
                    endRadius: 260
                )
            }
        }
    }
}

#Preview {
    HStack {
        HeatBackdrop(heats: [.lit]).frame(width: 160, height: 160).clipShape(.rect(cornerRadius: 22))
        HeatBackdrop(heats: [.lit, .troubled]).frame(width: 160, height: 160).clipShape(.rect(cornerRadius: 22))
        HeatBackdrop(heats: [.cold]).frame(width: 160, height: 160).clipShape(.rect(cornerRadius: 22))
    }
    .padding()
}
