import SwiftUI

/// The actions that fit the resource's state, for the detail toolbar: the likely one as a button, the rest in a menu
/// beside it. The Mac draws the pair as one split button.
struct ResourceLifecycleControl: View {
    var resource: ResourceSummary
    var pendingAction: ResourceAction?
    var onAction: (ResourceAction) -> Void

    private var actions: [ResourceAction] {
        ResourceAction.available(for: resource)
    }

    var body: some View {
        if let lead = actions.first {
            let rest = Array(actions.dropFirst())
            Group {
                if rest.isEmpty {
                    Button {
                        onAction(lead)
                    } label: {
                        label(lead)
                    }
                    .help(lead.explanation(for: resource.kind))
                    .disabled(lead.isBlocked(by: pendingAction))
                } else {
                    Menu {
                        ForEach(rest) { action in
                            Button(action == .stop ? "Stop…" : action.title, systemImage: action.systemImage) {
                                onAction(action)
                            }
                            .help(action.explanation(for: resource.kind))
                            .disabled(action.isBlocked(by: pendingAction))
                        }
                    } label: {
                        label(lead)
                    } primaryAction: {
                        onAction(lead)
                    }
                    .help(lead.explanation(for: resource.kind))
                    .disabled(actions.allSatisfy { $0.isBlocked(by: pendingAction) })
                }
            }
            // The likely action, unless it takes the resource down.
            .tint(lead == .stop || lead == .cancelDeployment ? nil : .ember)
            .buttonStyle(.borderedProminent)
            .background { shortcuts }
            .animation(.snappy, value: actions)
        }
    }

    /// The toolbar draws a symbol at the size of its icon-only buttons, which looks heavy beside a title.
    private func label(_ action: ResourceAction) -> some View {
        Label {
            Text(action.title)
        } icon: {
            Image(systemName: action.systemImage)
                .imageScale(.small)
        }
        .labelStyle(.titleAndIcon)
    }

    /// A menu's items only answer their shortcuts while it is open, so the shortcuts live on buttons of their own.
    private var shortcuts: some View {
        ZStack {
            ForEach(actions) { action in
                if let shortcut = action.shortcut {
                    Button(action.title) { onAction(action) }
                        .keyboardShortcut(shortcut)
                        .disabled(action.isBlocked(by: pendingAction))
                }
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

extension ResourceAction {
    /// Shortcuts for the actions that do not take anything down.
    fileprivate var shortcut: KeyboardShortcut? {
        switch self {
        case .start: KeyboardShortcut("s", modifiers: [.command, .shift])
        case .deploy: KeyboardShortcut("d", modifiers: [.command, .shift])
        case .restart: KeyboardShortcut("r", modifiers: [.command, .shift])
        case .stop, .cancelDeployment: nil
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ResourceLifecycleControl(
            resource: ResourceSummary(route: .application("web"), name: "web", status: "running:healthy"),
            onAction: { _ in }
        )
        ResourceLifecycleControl(
            resource: ResourceSummary(route: .database("pg"), name: "postgres", status: "exited"),
            onAction: { _ in }
        )
    }
    .padding(40)
}
