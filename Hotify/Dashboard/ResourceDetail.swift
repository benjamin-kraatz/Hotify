import CoolifyAPI
import SwiftUI

/// Deployments, previews, and logs for one application, database, or service.
struct ResourceDetailScreen: View {
    var client: CoolifyClient?
    var route: ResourceRoute
    var title: String
    var status: String
    var isBusy: Bool
    var onStart: () -> Void
    var onRestart: () -> Void
    var onStop: () -> Void

    @State private var model: ResourceDetailModel

    init(
        client: CoolifyClient?,
        route: ResourceRoute,
        title: String,
        status: String,
        isBusy: Bool,
        model: ResourceDetailModel = ResourceDetailModel(),
        onStart: @escaping () -> Void,
        onRestart: @escaping () -> Void,
        onStop: @escaping () -> Void
    ) {
        self.client = client
        self.route = route
        self.title = title
        self.status = status
        self.isBusy = isBusy
        self.onStart = onStart
        self.onRestart = onRestart
        self.onStop = onStop
        _model = State(initialValue: model)
    }

    var body: some View {
        ResourceDetail(
            title: title,
            status: status,
            logs: model.logs,
            deployments: model.deployments,
            showsDeployments: route.showsDeployments,
            loadError: model.loadError,
            actionError: model.actionError,
            isLoading: model.isLoading,
            isBusy: isBusy,
            isDeploying: model.isDeploying,
            onRefresh: { Task { await model.refresh() } },
            onDeploy: { Task { await model.deploy() } },
            onStart: onStart,
            onRestart: onRestart,
            onStop: onStop
        )
        .task(id: route) {
            guard let client else { return }
            model.prepare(client, route: route)
            while !Task.isCancelled {
                await model.refresh()
                if Task.isCancelled { return }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
}

/// The detail layout. Takes plain values so a preview does not need a client.
struct ResourceDetail: View {
    var title: String
    var status: String
    var logs: String
    var deployments: [DeploymentLine]
    var showsDeployments: Bool
    var loadError: String?
    var actionError: String?
    var isLoading: Bool
    var isBusy: Bool
    var isDeploying: Bool
    var onRefresh: () -> Void
    var onDeploy: () -> Void
    var onStart: () -> Void
    var onRestart: () -> Void
    var onStop: () -> Void

    private var production: [DeploymentLine] {
        deployments.filter { !$0.isPreview }
    }

    private var previews: [DeploymentLine] {
        deployments.filter(\.isPreview)
    }

    var body: some View {
        List {
            if let loadError {
                Text(loadError)
            }
            if let actionError {
                Text(actionError)
            }
            Text(status)
            HStack {
                Button("Start", action: onStart)
                Button("Restart", action: onRestart)
                Button("Stop", action: onStop)
                if showsDeployments {
                    Button("Deploy", action: onDeploy)
                        .disabled(isDeploying)
                }
            }
            .buttonStyle(.borderless)
            .disabled(isBusy)
            if showsDeployments {
                deploymentSections
            }
            Section("Logs") {
                if isLoading, logs.isEmpty {
                    Text("Loading")
                } else if logs.isEmpty {
                    Text("No logs")
                } else {
                    Text(logs)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle(title)
        .toolbar {
            Button("Refresh", action: onRefresh)
        }
    }

    @ViewBuilder
    private var deploymentSections: some View {
        Section("Deployments") {
            if production.isEmpty {
                Text(isLoading ? "Loading" : "No deployments")
            } else {
                ForEach(production) { row in
                    deploymentRow(row)
                }
            }
        }
        if !previews.isEmpty {
            Section("Previews") {
                ForEach(previews) { row in
                    deploymentRow(row)
                }
            }
        }
    }

    private func deploymentRow(_ row: DeploymentLine) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.status)
            if !row.detail.isEmpty {
                Text(row.detail)
            }
            if let url = row.url {
                Link(url.absoluteString, destination: url)
            }
        }
    }
}

#Preview("Application") {
    NavigationStack {
        applicationDetailPreview()
    }
}

#Preview("Database") {
    NavigationStack {
        databaseDetailPreview()
    }
}

private func applicationDetailPreview() -> some View {
    let model = ResourceDetailModel()
    model.logs = "2026-09-29T08:00:00Z listening on 3000\n2026-09-29T08:00:01Z ready"
    model.deployments = [
        DeploymentLine(
            id: "prod",
            status: "finished",
            detail: "abc1234",
            isPreview: false,
            url: nil
        ),
        DeploymentLine(
            id: "preview",
            status: "finished",
            detail: "PR 18 def5678",
            isPreview: true,
            url: URL(string: "https://pr-18.example.com")
        ),
    ]
    return ResourceDetailScreen(
        client: nil,
        route: .application("app"),
        title: "convex",
        status: "running:healthy",
        isBusy: false,
        model: model,
        onStart: {},
        onRestart: {},
        onStop: {}
    )
}

private func databaseDetailPreview() -> some View {
    let model = ResourceDetailModel()
    model.logs = "2026-09-29T08:00:00Z database system is ready to accept connections"
    return ResourceDetailScreen(
        client: nil,
        route: .database("db"),
        title: "postgres",
        status: "running:healthy",
        isBusy: false,
        model: model,
        onStart: {},
        onRestart: {},
        onStop: {}
    )
}
