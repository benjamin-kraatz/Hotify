import CoolifyAPI
import Foundation

/// Where an application's code comes from, as the Settings tab edits it: a repository's branch and the commit manual
/// deploys build, or a Docker image's tag.
struct ApplicationSource: Hashable {
    enum Kind: Hashable {
        /// Built from a repository, as Coolify stores its address.
        case git(repository: String)
        /// Pulled from a registry, by image name without the tag.
        case image(name: String)
    }

    var kind: Kind
    var branch = ""
    /// Whether manual deploys build `commit` rather than the branch's latest.
    var isPinned = false
    var commit = ""
    var tag = ""
    /// Whether a push to the branch deploys. A push deploys the pushed commit, pinned or not.
    var deploysOnPush = true

    /// `nil` for an application with neither a repository nor an image, such as one built from a pasted Dockerfile.
    init?(application: Application) {
        if application.isDockerImage, let name = application.dockerRegistryImageName, !name.isEmpty {
            kind = .image(name: name)
            tag = application.dockerRegistryImageTag ?? ""
        } else if let repository = application.gitRepository, !repository.isEmpty {
            kind = .git(repository: repository)
            branch = application.gitBranch ?? ""
            if let pinned = application.pinnedCommit {
                isPinned = true
                commit = pinned
            }
        } else {
            return nil
        }
        deploysOnPush = application.settings?.isAutoDeployEnabled ?? true
    }

    init(kind: Kind, branch: String = "", isPinned: Bool = false, commit: String = "", tag: String = "") {
        self.kind = kind
        self.branch = branch
        self.isPinned = isPinned
        self.commit = commit
        self.tag = tag
    }

    var isImage: Bool {
        if case .image = kind { true } else { false }
    }

    /// The repository on github.com, whose commits Hotify can list. `nil` for any other host.
    var gitHubRepository: GitHubRepository? {
        guard case .git(let repository) = kind else { return nil }
        return try? GitHubRepository(repository)
    }

    /// The commit Coolify should store: the pinned one, or `HEAD` for the branch's latest.
    var storedCommit: String {
        let commit = commit.trimmingCharacters(in: .whitespaces)
        return isPinned && !commit.isEmpty ? commit : "HEAD"
    }

    var trimmedBranch: String { branch.trimmingCharacters(in: .whitespaces) }
    var trimmedTag: String { tag.trimmingCharacters(in: .whitespaces) }

    /// What changed since `saved`, written into `update`.
    func write(changesFrom saved: Self, into update: inout ApplicationUpdate) {
        switch kind {
        case .git:
            if trimmedBranch != saved.trimmedBranch { update.gitBranch = trimmedBranch }
            if storedCommit != saved.storedCommit { update.gitCommitSHA = storedCommit }
            if deploysOnPush != saved.deploysOnPush { update.isAutoDeployEnabled = deploysOnPush }
        case .image:
            if trimmedTag != saved.trimmedTag { update.dockerRegistryImageTag = trimmedTag }
        }
    }

    /// The first thing Coolify would refuse, by its own rules for these fields.
    var problem: String? {
        switch kind {
        case .git:
            if trimmedBranch.isEmpty { return "A branch is required." }
            if isPinned {
                let commit = commit.trimmingCharacters(in: .whitespaces)
                if commit.isEmpty { return "Enter the commit to pin, or pick the latest." }
                if !Self.isCommit(commit) { return "A commit is a SHA, such as 528a020." }
            }
        case .image:
            if !Self.isTag(trimmedTag) {
                return "A tag is up to 128 letters, digits, and . _ -, such as 1.4.2 or latest."
            }
        }
        return nil
    }

    /// Coolify's rule for `git_commit_sha`, which also takes a branch or tag name.
    static func isCommit(_ text: String) -> Bool {
        text.range(of: #"^[a-zA-Z0-9][a-zA-Z0-9._\-/]*$"#, options: .regularExpression) != nil
    }

    /// Docker's rule for an image tag.
    static func isTag(_ text: String) -> Bool {
        text.range(of: #"^[a-zA-Z0-9_][a-zA-Z0-9._\-]{0,127}$"#, options: .regularExpression) != nil
    }
}
