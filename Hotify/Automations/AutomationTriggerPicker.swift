import SwiftUI

/// The events an automation can wait for, as cards to choose one from. The chosen card is lit in the brand red, with
/// its symbol filled. On iPhone there is one card, since it only runs a Shortcut when you tap Run.
struct AutomationTriggerPicker: View {
    @Binding var selection: AutomationTrigger

    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
            ForEach(AutomationTrigger.available) { trigger in
                TriggerCard(trigger: trigger, isSelected: trigger == selection) {
                    selection = trigger
                }
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: selection)
    }
}

private struct TriggerCard: View {
    var trigger: AutomationTrigger
    var isSelected: Bool
    var select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: trigger.systemImage)
                        .symbolVariant(isSelected ? .fill : .none)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.ember : Color.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            (isSelected ? Color.ember : Color.secondary).opacity(0.12),
                            in: .rect(cornerRadius: 8, style: .continuous)
                        )
                        .contentTransition(.symbolEffect(.replace))
                    Text(trigger.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Text(trigger.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
            .background(
                isSelected ? Color.ember.opacity(0.1) : Color.primary.opacity(0.045),
                in: .rect(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Color.ember.opacity(0.6) : Color.clear, lineWidth: 1.5)
            }
            .contentShape(.rect(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    @Previewable @State var selection = AutomationTrigger.available[0]
    AutomationTriggerPicker(selection: $selection)
        .padding()
        .frame(width: 520)
}
