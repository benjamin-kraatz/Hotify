#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit

/// A deploy started on this iPhone, on the Lock Screen and in the Dynamic Island: the flame, the resource, the stage,
/// and how long it has run. When Hotify can no longer update it, it says so instead of guessing.
struct DeploymentLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DeploymentActivityAttributes.self) { context in
            DeploymentActivityView(
                attributes: context.attributes, state: context.state, isStale: context.isStale
            )
            .widgetURL(context.attributes.link)
        } dynamicIsland: { context in
            let state = context.state
            let attributes = context.attributes
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    FlameGlyph(heat: state.stage.heat, height: 30)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(attributes.resourceName)
                            .font(.headline)
                            .lineLimit(1)
                        Text(state.stage.label)
                            .font(.subheadline)
                            .foregroundStyle(state.stage.heat.tint)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    DeploymentElapsed(attributes: attributes, state: state)
                        .font(.subheadline.monospacedDigit())
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.isStale, !state.stage.isOver {
                        Text("Open Hotify to update")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let place = attributes.placeName {
                        Text(place)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                FlameGlyph(heat: state.stage.heat, height: 16)
            } compactTrailing: {
                DeploymentElapsed(attributes: attributes, state: state)
                    .font(.caption.monospacedDigit())
                    .frame(maxWidth: 52)
            } minimal: {
                FlameGlyph(heat: state.stage.heat, height: 16)
            }
            .widgetURL(attributes.link)
            .keylineTint(Color("ember"))
        }
    }
}

/// The Lock Screen's banner for a deploy.
struct DeploymentActivityView: View {
    var attributes: DeploymentActivityAttributes
    var state: DeploymentActivityAttributes.ContentState
    var isStale: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            FlameGlyph(heat: state.stage.heat, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(attributes.resourceName)
                    .font(.headline)
                    .lineLimit(1)
                Text(state.stage.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(state.stage.heat.tint)
                if isStale, !state.stage.isOver {
                    Text("Open Hotify to update")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let place = attributes.placeName {
                    Text(place)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            DeploymentElapsed(attributes: attributes, state: state)
                .font(.title3.monospacedDigit())
        }
        .padding(16)
    }
}

/// How long the deploy has run, counting while it runs and fixed once it ends.
struct DeploymentElapsed: View {
    var attributes: DeploymentActivityAttributes
    var state: DeploymentActivityAttributes.ContentState

    var body: some View {
        if state.stage.isOver {
            Text(
                Duration.seconds(max(0, state.updatedAt.timeIntervalSince(attributes.startedAt)).rounded())
                    .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow))
            )
            .foregroundStyle(.secondary)
        } else {
            Text(timerInterval: attributes.startedAt...Date.distantFuture, countsDown: false)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview(
    "Lock Screen", as: .content,
    using: DeploymentActivityAttributes(
        instanceID: UUID(), applicationUUID: "web", deploymentUUID: "d1", resourceName: "marketing-site",
        placeName: "Website · production", startedAt: .now.addingTimeInterval(-74))
) {
    DeploymentLiveActivity()
} contentStates: {
    DeploymentActivityAttributes.ContentState(stage: .building, updatedAt: .now)
    DeploymentActivityAttributes.ContentState(stage: .finished, updatedAt: .now)
    DeploymentActivityAttributes.ContentState(stage: .failed, updatedAt: .now)
}
#endif
