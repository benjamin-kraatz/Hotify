import CoolifyAPI
import SwiftUI

/// One scope's shared variables in the detail column: the team, or a server.
///
/// The project page hosts the list itself, with a section per environment. This screen is that list for a single
/// scope. It says when the instance is not connected, and it does not push another navigation stack.
struct SharedVariableScreen: View {
    var client: CoolifyClient?
    var scope: SharedVariableScope
    /// The section's title, such as the team or the server.
    var sectionTitle: String
    /// The toolbar title, such as `Team Variables`.
    var navigationTitle: String
    var back: DetailBack?

    @State private var model: SharedVariablesModel

    init(
        client: CoolifyClient?,
        scope: SharedVariableScope,
        sectionTitle: String,
        navigationTitle: String,
        back: DetailBack? = nil,
        model: SharedVariablesModel = SharedVariablesModel()
    ) {
        self.client = client
        self.scope = scope
        self.sectionTitle = sectionTitle
        self.navigationTitle = navigationTitle
        self.back = back
        _model = State(initialValue: model)
    }

    var body: some View {
        Group {
            if client == nil, !model.hasLoaded {
                ContentUnavailableView(
                    "Not connected",
                    systemImage: "wifi.slash",
                    description: Text("This instance is not connected.")
                )
            } else {
                SharedVariableList(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(navigationTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .replacesSystemBack(back != nil)
        .toolbar {
            DetailNavigation(title: navigationTitle, back: back)
        }
        .task(id: client == nil) {
            guard let client else { return }
            model.prepare(client)
            model.track(scope: scope, title: sectionTitle)
        }
        .onChange(of: sectionTitle) { _, title in
            guard !model.sections.isEmpty else { return }
            model.track(scope: scope, title: title)
        }
    }
}

#Preview("Locked") {
    NavigationStack {
        SharedVariableScreen(
            client: nil,
            scope: .team,
            sectionTitle: "Root Team",
            navigationTitle: "Team Variables",
            back: DetailBack(title: "Dashboard") {},
            model: previewVariables(scope: .team, title: "Root Team")
        )
    }
    .environment(VariableLock(isRequired: true))
    .frame(width: 560, height: 560)
}

#Preview("Open") {
    NavigationStack {
        SharedVariableScreen(
            client: nil,
            scope: .server("localhost"),
            sectionTitle: "localhost",
            navigationTitle: "Server Variables",
            back: DetailBack(title: "localhost") {},
            model: previewVariables(scope: .server("localhost"), title: "localhost")
        )
    }
    .environment(VariableLock(isRequired: false))
    .frame(width: 560, height: 560)
}

#Preview("Empty") {
    NavigationStack {
        SharedVariableScreen(
            client: nil,
            scope: .team,
            sectionTitle: "Root Team",
            navigationTitle: "Team Variables",
            back: DetailBack(title: "Dashboard") {},
            model: SharedVariablesModel(
                sections: [SharedVariableSection(scope: .team, title: "Root Team")],
                hasLoaded: true
            )
        )
    }
    .environment(VariableLock(isRequired: false))
    .frame(width: 560, height: 420)
}

#Preview("Not connected") {
    NavigationStack {
        SharedVariableScreen(
            client: nil,
            scope: .team,
            sectionTitle: "Team",
            navigationTitle: "Team Variables",
            back: DetailBack(title: "Dashboard") {}
        )
    }
    .frame(width: 560, height: 420)
}

private func previewVariables(scope: SharedVariableScope, title: String) -> SharedVariablesModel {
    SharedVariablesModel(
        sections: [
            SharedVariableSection(
                scope: scope,
                title: title,
                lines: [
                    VariableLine(id: "1", key: "API_URL", value: "https://api.example.com", isLiteral: true),
                    VariableLine(id: "2", key: "LOG_LEVEL", value: "warn"),
                ]
            )
        ],
        hasLoaded: true
    )
}
