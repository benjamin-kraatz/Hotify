import CoolifyAPI
import SwiftUI

/// A channel's symbol in a rounded tile, lit in ember while the channel is on.
struct AlertChannelIcon: View {
    var channel: NotificationChannel
    var isOn: Bool

    var body: some View {
        Image(systemName: channel.systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isOn ? AnyShapeStyle(.ember) : AnyShapeStyle(.secondary))
            .frame(width: 32, height: 32)
            .background(
                (isOn ? Color.ember : Color.secondary).opacity(0.12),
                in: .rect(cornerRadius: 9, style: .continuous)
            )
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack {
        ForEach(NotificationChannel.allCases) { channel in
            AlertChannelIcon(channel: channel, isOn: channel == .discord)
        }
    }
    .padding()
}
