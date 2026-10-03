import SwiftUI
import WidgetKit

/// Hotify's widgets and controls.
@main
struct HotifyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PinnedResourcesWidget()
        InstancePulseWidget()
        NeedsAttentionWidget()
        RecentDeploymentsWidget()
        BackupsWidget()
        ResourcePowerControl()
        ResourceButtonControl()
        #if os(iOS)
        DeploymentLiveActivity()
        #endif
    }
}
