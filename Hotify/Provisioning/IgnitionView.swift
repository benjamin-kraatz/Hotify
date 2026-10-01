import SwiftUI

/// The new service coming up. The flame flickers while its containers start, then catches, and can be stoked.
struct IgnitionView: View {
    var name: String
    var ignition: Ignition
    /// The addresses the service answers on, offered once it runs.
    var addresses: [URL]
    var onOpen: () -> Void
    var onClose: () -> Void

    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRunning: Bool { ignition.phase == .running }

    private var status: String {
        switch ignition.phase {
        case .starting: "Starting…"
        case .running: "Running"
        case .stalled: "Taking longer than usual"
        case .stopped: "Stopped again"
        }
    }

    private var detail: String {
        switch ignition.phase {
        case .starting:
            "Coolify is pulling images and starting \(containerCount). The first start can take a few minutes."
        case .running:
            "Every container is up. It's in your dashboard now, with its logs and variables."
        case .stalled:
            "A large image may still be pulling. Hotify keeps watching, or open it to read its logs."
        case .stopped:
            "Its containers came up, then stopped. Its logs usually say why, often a setting it needs."
        }
    }

    private var containerCount: String {
        ignition.containers.count == 1 ? "1 container" : "\(ignition.containers.count) containers"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                flame
                    .frame(height: 150, alignment: .bottom)
                    .padding(.top, 24)

                VStack(spacing: 8) {
                    Text(name)
                        .font(.display(.title))
                        .multilineTextAlignment(.center)
                    HStack(spacing: 8) {
                        Text(status)
                            .fontWeight(.semibold)
                            .foregroundStyle(ignition.heat.tint)
                            .contentTransition(.interpolate)
                        if !isRunning {
                            elapsed
                        }
                    }
                    .font(.headline)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 420)
                }

                if isRunning, !addresses.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(addresses, id: \.self) { address in
                            Link(destination: address) {
                                Label(address.host() ?? address.absoluteString, systemImage: "arrow.up.right")
                                    .labelStyle(.titleAndIcon)
                            }
                            .glassButton()
                        }
                    }
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }

                if !ignition.containers.isEmpty {
                    containers
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { openBar }
        .animation(
            reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.6, bounce: 0.25), value: ignition.phase
        )
        .animation(.snappy, value: ignition.containers)
        .sensoryFeedback(trigger: ignition.phase) { _, phase in
            switch phase {
            case .running: .success
            case .stalled, .stopped: .warning
            case .starting: nil
            }
        }
        .onChange(of: ignition.phase) { _, _ in
            AccessibilityNotification.Announcement("\(name): \(status)").post()
        }
        .navigationTitle(name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", action: onClose)
            }
        }
    }

    @ViewBuilder
    private var flame: some View {
        if isRunning {
            // Lit for good. It flares as it catches and burns brighter when touched.
            StokableFlame(height: 112, headroom: 24, ignitesOnAppear: true)
                .transition(.scale(scale: 0.7, anchor: .bottom).combined(with: .opacity))
        } else {
            FlameGlyph(heat: ignition.heat, height: 112)
                .transition(.opacity)
        }
    }

    private var elapsed: some View {
        TimelineView(.periodic(from: ignition.startedAt, by: 1)) { context in
            let seconds = max(0, Int(context.date.timeIntervalSince(ignition.startedAt)))
            Text(verbatim: String(format: "%d:%02d", seconds / 60, seconds % 60))
                .font(.headline.monospacedDigit())
                .foregroundStyle(.tertiary)
                .contentTransition(.numericText())
        }
        .accessibilityHidden(true)
    }

    private var containers: some View {
        VStack(spacing: 0) {
            ForEach(Array(ignition.containers.enumerated()), id: \.element.id) { index, container in
                if index > 0 {
                    Divider().padding(.leading, 44)
                }
                HStack(spacing: 12) {
                    FlameGlyph(heat: container.heat, height: 18)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(container.name)
                            .fontWeight(.medium)
                        if let image = container.image {
                            Text(verbatim: image)
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 12)
                    Text(StatusLabel.text(for: container.status))
                        .font(.subheadline)
                        .foregroundStyle(
                            container.heat.needsAttention ? AnyShapeStyle(.glow) : AnyShapeStyle(.secondary)
                        )
                        .contentTransition(.interpolate)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
            }
        }
        .well()
        .frame(maxWidth: 480)
    }

    private var openBar: some View {
        HStack {
            Spacer(minLength: 0)
            Button(action: onOpen) {
                Label(
                    isRunning ? "Open \(name)" : "Follow in Hotify",
                    systemImage: isRunning ? "arrow.forward" : "text.alignleft")
            }
            .glassButton(prominent: isRunning)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
    }
}

#Preview("Starting") {
    NavigationStack {
        IgnitionView(
            name: "blog",
            ignition: Ignition(
                startedAt: .now.addingTimeInterval(-42),
                containers: [
                    ContainerSummary(id: 1, name: "ghost", status: "starting", image: "ghost:5"),
                    ContainerSummary(id: 2, name: "mysql", status: "running:healthy", image: "mysql:8.0"),
                ]
            ),
            addresses: [],
            onOpen: {},
            onClose: {}
        )
    }
    .frame(width: 720, height: 720)
}

#Preview("Running") {
    NavigationStack {
        IgnitionView(
            name: "blog",
            ignition: Ignition(
                containers: [
                    ContainerSummary(id: 1, name: "ghost", status: "running:healthy", image: "ghost:5"),
                    ContainerSummary(id: 2, name: "mysql", status: "running:healthy", image: "mysql:8.0"),
                ],
                phase: .running
            ),
            addresses: [URL(string: "https://blog.example.com")!],
            onOpen: {},
            onClose: {}
        )
    }
    .frame(width: 720, height: 720)
}
