import CoolifyAPI
import SwiftUI

/// A rollback waiting for the user to confirm it.
struct RollbackCandidate: Identifiable, Hashable {
    var image: RollbackImage
    var resourceName: String

    var id: String { image.tag }

    var title: String {
        guard let date = image.createdAtDate else {
            return "Roll back \(resourceName) to \(image.shortTag)?"
        }
        return "Roll back \(resourceName) to \(image.shortTag) from \(date.formatted(.relative(presentation: .named)))?"
    }

    var message: String {
        image.isCommit
            ? "Coolify runs the image it built from this commit. The next deploy brings back the latest commit."
            : "Coolify runs this image again. The next deploy goes back to the tag in the application's settings."
    }
}

extension View {
    /// Asks before a rollback, because it replaces what runs in production.
    func rollbackConfirmation(
        for candidate: Binding<RollbackCandidate?>,
        onConfirm: @escaping (RollbackImage) -> Void
    ) -> some View {
        confirmationDialog(
            candidate.wrappedValue?.title ?? "",
            isPresented: Binding(
                get: { candidate.wrappedValue != nil },
                set: { isPresented in
                    if !isPresented {
                        candidate.wrappedValue = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: candidate.wrappedValue
        ) { candidate in
            // Destructive, like Stop, so Return doesn't confirm it on the Mac.
            Button("Roll Back", role: .destructive) {
                onConfirm(candidate.image)
            }
        } message: { candidate in
            Text(candidate.message)
        }
    }
}
