import SwiftUI
import WidgetKit

/// Draws an Instance widget for its size.
struct InstancePulseView: View {
    var entry: PulseEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(for: .widget) {
                HeatBackdrop(heats: entry.pulse.map { [$0.heat] } ?? [])
            }
    }

    @ViewBuilder
    private var content: some View {
        if let pulse = entry.pulse {
            switch family {
            #if os(iOS)
            case .accessoryCircular:
                PulseRing(pulse: pulse)
            case .accessoryRectangular:
                PulseAccessoryLines(pulse: pulse)
            case .accessoryInline:
                PulseInline(pulse: pulse)
            #endif
            default:
                PulseTile(pulse: pulse)
            }
        } else {
            switch family {
            #if os(iOS)
            case .accessoryInline:
                Text("No instance yet")
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    FlameGlyph(heat: .cold, height: 22)
                }
            #endif
            default:
                VStack(alignment: .leading, spacing: 4) {
                    FlameGlyph(heat: .cold, height: 26)
                    Spacer(minLength: 0)
                    Text("No instance yet").font(.headline)
                    Text("Add a Coolify instance in Hotify.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }
}

/// What the line under the count says: the problem, else what wants a look, else that all is calm.
private func pulseDetail(_ pulse: InstancePulse) -> String {
    if let problem = pulse.problem { return problem.message(instanceName: pulse.instanceName) }
    if pulse.attention == 1, let name = pulse.attentionNames.first { return "\(name) needs a look" }
    if pulse.attention > 1 { return "\(pulse.attention) need a look" }
    return pulse.running == pulse.total ? "All running" : "\(pulse.total - pulse.running) stopped"
}

/// The Home Screen tile: the instance's name, how many run, and a strip of every resource.
struct PulseTile: View {
    var pulse: InstancePulse

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                FlameGlyph(heat: pulse.heat, height: 28)
                    .widgetAccentable()
                Spacer()
                if let checkedAt = pulse.checkedAt {
                    Text(
                        .currentDate,
                        format: .reference(to: checkedAt, allowedFields: [.minute, .hour, .day], maxFieldCount: 1)
                    )
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text(pulse.instanceName)
                .font(.display(.subheadline))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(pulse.running)")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(pulse.running > 0 ? AnyShapeStyle(.ember) : AnyShapeStyle(.secondary))
                    .widgetAccentable()
                Text("of \(pulse.total) running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if pulse.total > 0 {
                HeatStrip(heats: pulse.heats, height: 6)
                    .padding(.vertical, 5)
                    .widgetAccentable()
            }
            Text(pulseDetail(pulse))
                .font(.caption2)
                .foregroundStyle(
                    pulse.attention > 0 || pulse.problem != nil ? AnyShapeStyle(.glow) : AnyShapeStyle(.secondary)
                )
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

#if os(iOS)
/// A ring that fills with the share of resources running, the instance's flame inside.
struct PulseRing: View {
    var pulse: InstancePulse

    var body: some View {
        Gauge(value: Double(pulse.running), in: 0...Double(max(pulse.total, 1))) {
            Text(pulse.instanceName)
        } currentValueLabel: {
            VStack(spacing: 0) {
                FlameGlyph(heat: pulse.heat, height: 16)
                    .widgetAccentable()
                Text("\(pulse.running)/\(pulse.total)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.7)
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }
}

/// The instance's name, the strip, and the count, in the Lock Screen's rectangle.
struct PulseAccessoryLines: View {
    var pulse: InstancePulse

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                FlameGlyph(heat: pulse.heat, height: 14)
                    .widgetAccentable()
                Text(pulse.instanceName)
                    .font(.headline)
                    .lineLimit(1)
            }
            Text("\(pulse.running) of \(pulse.total) running")
                .font(.subheadline)
            Text(pulseDetail(pulse))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One line above the clock: `6 running · 1 needs a look`.
struct PulseInline: View {
    var pulse: InstancePulse

    var body: some View {
        // Above the clock only text and symbols draw, so the flame is the system's.
        Label {
            if let problem = pulse.problem {
                Text(problem.message(instanceName: pulse.instanceName))
            } else if pulse.attention > 0 {
                Text("\(pulse.running) running · \(pulse.attention) \(pulse.attention == 1 ? "needs" : "need") a look")
            } else {
                Text("\(pulse.running) of \(pulse.total) running")
            }
        } icon: {
            Image(systemName: pulse.running > 0 ? "flame.fill" : "flame")
        }
    }
}

#Preview("Ring", as: .accessoryCircular) {
    InstancePulseWidget()
} timeline: {
    PulseEntry(date: .now, pulse: .sample)
}

#Preview("Inline", as: .accessoryInline) {
    InstancePulseWidget()
} timeline: {
    PulseEntry(date: .now, pulse: .sample)
}
#endif

#Preview("Tile", as: .systemSmall) {
    InstancePulseWidget()
} timeline: {
    PulseEntry(date: .now, pulse: .sample)
}
