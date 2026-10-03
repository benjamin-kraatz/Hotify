import CoolifyAPI
import SwiftUI

/// The toolbar's Versions menu: the images Coolify kept for an application to roll back to, newest first, with the
/// running one marked, then a way to deploy any other version. When there is no image to go back to, it says why
/// rather than going missing.
struct VersionsMenu: View {
    var images: [RollbackImage]
    var hasLoaded: Bool
    var loadError: String?
    /// The history, for the commit message of each image.
    var deployments: [DeploymentLine]
    var isBusy: Bool
    var onChoose: (RollbackImage) -> Void
    /// Opens the sheet that deploys a commit or tag. `nil` leaves the item out.
    var onDeployVersion: (() -> Void)?

    private var hasEarlierImage: Bool { images.contains { !$0.isCurrent } }

    var body: some View {
        Menu {
            if !images.isEmpty {
                Section("Images Coolify Kept") {
                    ForEach(images) { image in
                        Button {
                            onChoose(image)
                        } label: {
                            let message = message(for: image)
                            Text(message ?? image.shortTag)
                            Text(detail(for: image, showsTag: message != nil))
                        }
                        .disabled(image.isCurrent)
                    }
                }
            }
            if !note.isEmpty {
                // One short item per line. A Mac menu doesn't wrap, so a long one would widen the whole menu.
                Section {
                    ForEach(note, id: \.self) { line in
                        Text(line)
                    }
                }
            }
            if let onDeployVersion {
                Section {
                    Button("Deploy a Version…", systemImage: "arrow.up.circle", action: onDeployVersion)
                }
            }
        } label: {
            Label("Versions", systemImage: "clock.arrow.circlepath")
        }
        .menuIndicator(.hidden)
        .help("Roll back to an image Coolify kept, or deploy another version")
        .disabled(isBusy)
    }

    /// Why the menu has nothing to choose, as short lines.
    private var note: [String] {
        if let loadError {
            return ["Couldn't list the images.", loadError]
        }
        guard hasLoaded else { return ["Looking for images…"] }
        if hasEarlierImage { return [] }
        // Coolify lists nothing while the server is unreachable, and keeps 2 images unless retention is off.
        let retention = "It keeps 2, or none if the server's retention is off."
        return images.isEmpty
            ? [
                "Coolify has no images of this application.", retention,
                "It lists none while the server is unreachable.",
            ]
            : ["Coolify kept no earlier image.", retention]
    }

    private func message(for image: RollbackImage) -> String? {
        deployments.first { !$0.isPreview && image.matches(commit: $0.commitSHA ?? $0.commit) && $0.message != nil }?
            .message
    }

    /// The tag, unless it is already the title, then the image's age and whether it runs.
    private func detail(for image: RollbackImage, showsTag: Bool) -> String {
        var parts = showsTag ? [image.shortTag] : []
        if let date = image.createdAtDate {
            parts.append(date.formatted(.relative(presentation: .named)))
        }
        if image.isCurrent {
            parts.append("running")
        }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    VersionsMenu(
        images: [
            RollbackImage(
                tag: "5aa01e77c3d4e5f60718293a4b5c6d7e8f901234", createdAt: "2026-09-30 16:21:30 +0000 UTC",
                isCurrent: true),
            RollbackImage(tag: "1b2c3d4e5f60718293a4b5c6d7e8f9012345678a", createdAt: "2026-09-28 09:00:40 +0000 UTC"),
        ],
        hasLoaded: true,
        loadError: nil,
        deployments: [
            DeploymentLine(id: "1", status: "finished", commit: "5aa01e7", message: "fix: retry on 502")
        ],
        isBusy: false,
        onChoose: { _ in },
        onDeployVersion: {}
    )
    .padding()
}
