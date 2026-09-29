import SwiftUI

/// What the flames and the action buttons mean, for the kind of resource on screen.
struct ResourceGuide: View {
    var kind: ResourceKind

    private var actions: [ResourceAction] {
        kind == .application ? [.start, .deploy, .restart, .stop, .cancelDeployment] : [.start, .restart, .stop]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                section("Status") {
                    GuideRow(title: "Running", detail: "Up and serving. The flame is lit.") {
                        FlameGlyph(heat: .lit, height: 26)
                    }
                    GuideRow(
                        title: "On its way",
                        detail:
                            "Starting, stopping, restarting, or building. The flame flickers until Coolify reports back."
                    ) {
                        FlameGlyph(heat: .warming, height: 26)
                    }
                    GuideRow(
                        title: "Needs a look",
                        detail: "Unhealthy, degraded, or the last deployment failed. The flame glows amber."
                    ) {
                        FlameGlyph(heat: .troubled, height: 26)
                    }
                    GuideRow(title: "Stopped", detail: "Not running. Its data and settings stay in place.") {
                        FlameGlyph(heat: .cold, height: 26)
                    }
                }

                section("Actions") {
                    ForEach(actions) { action in
                        GuideRow(title: action.title, detail: Self.detail(for: action, kind: kind)) {
                            Image(systemName: action.systemImage)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Self.tint(for: action))
                        }
                    }
                }

                if kind == .service {
                    section("Containers in Logs") {
                        GuideRow(title: "Running", detail: "Filled flame. Pick it to read what the container prints.") {
                            containerIcon("flame.fill")
                        }
                        GuideRow(
                            title: "Stopped",
                            detail:
                                "Outlined flame. Coolify serves no logs for a stopped container. Some, like a migration, stop on purpose once their job is done."
                        ) {
                            containerIcon("flame")
                        }
                    }
                }

                if kind == .application {
                    Text("Every Start, Redeploy, and Restart adds an entry under Deployments, with how it went.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The same symbols the log view's container menu shows.
    private func containerIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.title3)
            .foregroundStyle(.ember)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private static func detail(for action: ResourceAction, kind: ResourceKind) -> String {
        switch (action, kind) {
        case (.start, .application):
            "Builds the latest commit and runs it. Coolify starts an app by deploying it, so there is no separate Deploy."
        case (.start, _):
            "Starts the containers again, with the data they had."
        case (.deploy, _):
            "Pulls the latest commit, builds it, and replaces the version that runs now. Use it to ship new code."
        case (.restart, .application):
            "Restarts the containers with the build they already have. Quick, and nothing is rebuilt."
        case (.restart, _):
            "Stops and starts the containers. Data stays."
        case (.stop, _):
            "Stops the containers. Volumes and data stay, and Hotify asks before it does this."
        case (.cancelDeployment, _):
            "Stops a build that is still running. What ran before keeps running."
        }
    }

    private static func tint(for action: ResourceAction) -> Color {
        switch action {
        case .start, .deploy: .ember
        case .restart: .glow
        case .stop, .cancelDeployment: .secondary
        }
    }
}

/// An icon in a soft tile, then a title and a sentence.
private struct GuideRow<Icon: View>: View {
    var title: String
    var detail: String
    @ViewBuilder var icon: Icon

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            icon
                .frame(width: 44, height: 44)
                .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A toolbar button that opens `ResourceGuide`: a sheet on iPhone and iPad, a popover on the Mac.
struct ResourceGuideButton: View {
    var kind: ResourceKind

    @State private var isShowing = false

    var body: some View {
        Button("What do these mean?", systemImage: "questionmark.circle") {
            isShowing = true
        }
        .help("What the flames and buttons mean")
        #if os(macOS)
        .popover(isPresented: $isShowing, arrowEdge: .bottom) {
            ResourceGuide(kind: kind)
            .frame(width: 400, height: 560)
        }
        #else
        .sheet(isPresented: $isShowing) {
            NavigationStack {
                ResourceGuide(kind: kind)
                .navigationTitle("Guide")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            isShowing = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        #endif
    }
}

#Preview("Application") {
    ResourceGuide(kind: .application)
        .frame(width: 400, height: 720)
}

#Preview("Service") {
    ResourceGuide(kind: .service)
        .frame(width: 400, height: 720)
}

#Preview("Database") {
    ResourceGuide(kind: .database)
        .frame(width: 400, height: 560)
}
