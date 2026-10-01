import CoolifyAPI
import SwiftUI

/// Where the previews space stands: the board, or one pull request.
enum PreviewPlace: Hashable {
    case board
    case preview(Int)
}

/// The previews of an application, in place of its production detail. It burns blue throughout, so it is never
/// mistaken for production, and production's actions stay out of reach while it is open.
struct PreviewSpace: View {
    var resourceName: String
    var application: String
    var previews: [PreviewLine]
    var model: PreviewsModel
    var client: CoolifyClient?
    @Binding var place: PreviewPlace?
    /// The build to follow when a preview opens, such as one the deploy sheet just queued.
    @Binding var followedDeployment: DeploymentLine?
    var isLoading: Bool
    var canLoadMore = false
    var onLoadMore: () -> Void = {}
    var onDeploy: () -> Void

    @State private var removalCandidate: PreviewLine?
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch place {
            case .preview(let number):
                PreviewDetail(
                    preview: preview(number),
                    model: model,
                    client: client,
                    application: application,
                    selectedDeployment: $followedDeployment,
                    onBack: {
                        followedDeployment = nil
                        place = .board
                    },
                    onRemove: { removalCandidate = $0 }
                )
                .id(number)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            case .board, nil:
                PreviewBoard(
                    resourceName: resourceName,
                    previews: previews,
                    model: model,
                    isLoading: isLoading,
                    canLoadMore: canLoadMore,
                    onLoadMore: onLoadMore,
                    onBack: { place = nil },
                    onDeploy: onDeploy,
                    onOpen: { number in
                        followedDeployment = nil
                        place = .preview(number)
                    },
                    onRemove: { removalCandidate = $0 }
                )
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .tint(.pilot)
        .animation(reduceMotion ? nil : .snappy, value: place)
        .confirmationDialog(
            removalCandidate.map { "Remove the preview of PR #\($0.number)?" } ?? "",
            isPresented: Binding(
                get: { removalCandidate != nil },
                set: { if !$0 { removalCandidate = nil } }
            ),
            titleVisibility: .visible,
            presenting: removalCandidate
        ) { preview in
            Button("Remove Preview", role: .destructive) {
                Task { await model.remove(preview.number) }
            }
        } message: { _ in
            Text(
                "Coolify stops its containers and deletes its volumes and networks. The pull request and \(resourceName) are not touched."
            )
        }
    }

    /// The preview by number. One the history has not listed yet gets a stand-in until it does.
    private func preview(_ number: Int) -> PreviewLine {
        previews.first { $0.number == number }
            ?? PreviewLine(
                number: number,
                deployments: [
                    followedDeployment ?? DeploymentLine(id: "pr-\(number)", status: "queued", pullRequest: number)
                ]
            )
    }
}

#Preview {
    @Previewable @State var place: PreviewPlace? = .board
    @Previewable @State var followed: DeploymentLine?
    PreviewSpace(
        resourceName: "marketing-site",
        application: "app",
        previews: [
            PreviewLine(
                number: 42,
                deployments: [DeploymentLine(id: "a", status: "finished", pullRequest: 42, startedAt: .now)],
                title: "Add a pricing page",
                branch: "feat/pricing"
            )
        ],
        model: PreviewsModel(),
        client: nil,
        place: $place,
        followedDeployment: $followed,
        isLoading: false,
        onDeploy: {}
    )
    .frame(width: 640, height: 720)
}
