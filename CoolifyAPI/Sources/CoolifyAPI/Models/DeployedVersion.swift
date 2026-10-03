import Foundation

/// A deployment of one version, queued by `deploy(_:version:restoring:)`.
public struct DeployedVersion: Sendable, Hashable {
    public var deploymentUUID: String
    /// Why the previous version couldn't be put back. The deployment is queued either way, but the application stays
    /// pinned to the version it deployed.
    public var restoreError: String?
}
