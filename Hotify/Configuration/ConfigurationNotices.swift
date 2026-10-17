import CoolifyAPI
import SwiftUI

/// What the last save left to say: a change that waits for a restart or redeploy, domains that are taken, a compose
/// file changed elsewhere, or why the save failed.
struct ConfigurationNotices: View {
    var model: ConfigurationModel
    var resource: ResourceSummary
    var pendingAction: ResourceAction?
    var onAction: (ResourceAction) -> Void

    /// The action that puts saved changes to use. A stopped resource picks them up when it next starts.
    private var applyAction: ResourceAction? {
        guard resource.heat != .cold else { return nil }
        return resource.kind == .application ? .deploy : .restart
    }

    private var applyMessage: String {
        switch applyAction {
        case .deploy: "Saved. It takes effect after a redeploy."
        case .restart:
            model.hasUnappliedCompose
                ? "Saved. The containers run the earlier compose file until a restart."
                : "Saved. It takes effect after a restart."
        default: "Saved. It takes effect on the next start."
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            if model.hasUnappliedChanges {
                ApplyBar(
                    kind: resource.kind,
                    message: applyMessage,
                    action: applyAction,
                    isBusy: pendingAction != nil || resource.isDeploying,
                    onApply: { action in
                        onAction(action)
                        model.hasUnappliedChanges = false
                    },
                    onDismiss: { model.hasUnappliedChanges = false }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            if model.hasComposeConflict {
                ComposeConflictNotice(
                    isSaving: model.isSaving,
                    onReplace: { Task { await model.save(replacingTheirCompose: true) } },
                    onTakeTheirs: { model.takeTheirCompose() }
                )
            }
            if !model.conflicts.isEmpty {
                ProblemNotice(problem: .conflicts(model.conflicts)) {
                    Task { await model.save(force: true) }
                }
            }
            if let saveError = model.saveError {
                NoticeBanner(message: saveError)
            }
            if let notice = model.notice {
                NoticeBanner(message: notice)
            }
            if model.restoredComposeEdits, model.hasComposeChanges, !model.hasComposeConflict {
                NoticeBanner(
                    message: "Your unsaved compose edits from earlier are back. Save them, or Revert.",
                    tone: .done,
                    systemImage: "arrow.uturn.backward.circle.fill"
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, hasNotices ? 12 : 0)
        .animation(.snappy, value: model.hasUnappliedChanges)
        .animation(.snappy, value: model.hasComposeConflict)
        .animation(.snappy, value: model.saveError)
        .animation(.snappy, value: model.conflicts)
        .animation(.snappy, value: model.notice)
        .animation(.snappy, value: model.restoredComposeEdits)
    }

    private var hasNotices: Bool {
        model.hasUnappliedChanges || model.hasComposeConflict || !model.conflicts.isEmpty || model.saveError != nil
            || model.notice != nil || (model.restoredComposeEdits && model.hasComposeChanges)
    }
}
