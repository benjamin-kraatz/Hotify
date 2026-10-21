import Foundation

/// The commands Coolify runs around each deployment of an application. Coolify keeps them as flat fields on the
/// application.
///
/// Both run on the server, through `docker exec <container> sh -c '<command>'`, and Coolify turns line breaks into
/// spaces first. The pre-deployment command runs in the container that is running before the new version starts, and
/// is skipped when none runs yet. Its failure fails the deployment. The post-deployment command runs in the new
/// container once it is up, and its failure is only logged.
///
/// With one container, Coolify ignores the container name. A Docker Compose application runs several, and Coolify
/// matches the name against the start of each, as `<service>-<application uuid>`, so the name is the compose service.
/// Without a name there, the pre-deployment command fails the deployment, and the post-deployment one is skipped.
/// Coolify 4.3 and 4.4 behave the same.
public struct DeploymentCommands: Codable, Sendable, Hashable {
    public var preDeployment: String?
    /// The compose service the pre-deployment command runs in.
    public var preDeploymentContainer: String?
    public var postDeployment: String?
    /// The compose service the post-deployment command runs in.
    public var postDeploymentContainer: String?

    enum CodingKeys: String, CodingKey {
        case preDeployment = "preDeploymentCommand"
        case preDeploymentContainer = "preDeploymentCommandContainer"
        case postDeployment = "postDeploymentCommand"
        case postDeploymentContainer = "postDeploymentCommandContainer"
    }

    public init(
        preDeployment: String? = nil,
        preDeploymentContainer: String? = nil,
        postDeployment: String? = nil,
        postDeploymentContainer: String? = nil
    ) {
        self.preDeployment = preDeployment
        self.preDeploymentContainer = preDeploymentContainer
        self.postDeployment = postDeployment
        self.postDeploymentContainer = postDeploymentContainer
    }

    /// Reads the flat fields from an application's own JSON object.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preDeployment = container.flexString(.preDeployment)
        preDeploymentContainer = container.flexString(.preDeploymentContainer)
        postDeployment = container.flexString(.postDeployment)
        postDeploymentContainer = container.flexString(.postDeploymentContainer)
    }

    /// Writes every field that has a value, flat into the update's own object. An empty command clears it.
    ///
    /// An empty container name stays out. Laravel turns it into `null`, and Coolify validates the name as a string
    /// that is not nullable, so it would answer 422. A name can be changed through the API, but not cleared.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(preDeployment, forKey: .preDeployment)
        try container.encodeIfPresent(preDeploymentContainer?.nonEmpty, forKey: .preDeploymentContainer)
        try container.encodeIfPresent(postDeployment, forKey: .postDeployment)
        try container.encodeIfPresent(postDeploymentContainer?.nonEmpty, forKey: .postDeploymentContainer)
    }

    public var isEmpty: Bool {
        self == Self()
    }

    /// Whether Coolify takes the text as a container name: a letter or digit, then letters, digits, and `. _ -`, up to
    /// 255 characters. Coolify 4.3 checks the same characters.
    public static func isContainerName(_ text: String) -> Bool {
        text.unicodeScalars.count <= 255
            && text.range(of: #"\A[a-zA-Z0-9][a-zA-Z0-9._\-]*\z"#, options: .regularExpression) != nil
    }
}
