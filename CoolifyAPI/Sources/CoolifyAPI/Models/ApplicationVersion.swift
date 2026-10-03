import Foundation

/// What an application deploys: a commit of a git application, or a tag of a Docker image application.
public enum ApplicationVersion: Sendable, Hashable {
    /// A commit SHA. `HEAD` is the branch's latest.
    case commit(String)
    case imageTag(String)

    /// The branch's latest commit, which is what an application without a pin deploys.
    public static let latestCommit = ApplicationVersion.commit("HEAD")

    /// The update that pins this version.
    var update: ApplicationUpdate {
        switch self {
        case .commit(let sha): ApplicationUpdate(gitCommitSHA: sha)
        case .imageTag(let tag): ApplicationUpdate(dockerRegistryImageTag: tag)
        }
    }
}
