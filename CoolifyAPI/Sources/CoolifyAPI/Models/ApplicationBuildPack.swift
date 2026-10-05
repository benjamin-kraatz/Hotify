import Foundation

/// How Coolify builds an application from a repository or a Dockerfile.
///
/// A Docker image application has no build pack: Coolify 4.3's dockerimage schema rejects the key.
public enum ApplicationBuildPack: String, Codable, Sendable, CaseIterable, Identifiable {
    case nixpacks
    case railpack
    case `static`
    case dockerfile
    case dockercompose

    public var id: String { rawValue }
}
