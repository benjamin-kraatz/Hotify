import SwiftUI

/// The toolbar's way into an application's previews: deploy one, browse them all, or jump to a recent one.
struct PreviewsMenu: View {
    var resourceName: String
    var previews: [PreviewLine]
    var isShowingPreviews: Bool
    var canDeploy: Bool
    var onDeploy: () -> Void
    var onShow: (PreviewPlace?) -> Void
    var onGitHubAccess: () -> Void

    var body: some View {
        Menu {
            Button("Deploy a Preview…", systemImage: "arrow.triangle.pull", action: onDeploy)
                .disabled(!canDeploy)
            if isShowingPreviews {
                Button("Back to \(resourceName)", systemImage: "flame") { onShow(nil) }
            } else {
                Button("Show Previews", systemImage: "square.grid.2x2") { onShow(.board) }
            }

            if !previews.isEmpty {
                Section("Recent") {
                    ForEach(previews.prefix(5)) { preview in
                        Button {
                            onShow(.preview(preview.number))
                        } label: {
                            Label {
                                Text(verbatim: preview.headline)
                                Text(verbatim: "#\(preview.number), \(preview.stateLabel)")
                            } icon: {
                                Image(systemName: preview.state.systemImage)
                            }
                        }
                    }
                }
            }

            Divider()
            Button("GitHub Access…", systemImage: "key", action: onGitHubAccess)
        } label: {
            Label("Previews", systemImage: "arrow.triangle.pull")
        }
        .help("Pull request previews")
    }
}

#Preview {
    NavigationStack {
        Text("marketing-site")
            .toolbar {
                ToolbarItem {
                    PreviewsMenu(
                        resourceName: "marketing-site",
                        previews: [
                            PreviewLine(
                                number: 42, deployments: [DeploymentLine(id: "a", status: "finished", pullRequest: 42)],
                                title: "Add a pricing page")
                        ],
                        isShowingPreviews: false,
                        canDeploy: true,
                        onDeploy: {},
                        onShow: { _ in },
                        onGitHubAccess: {}
                    )
                }
            }
    }
    .frame(width: 400, height: 200)
}
