import Foundation

/// How Coolify builds an application from its repository. Coolify keeps these as flat fields on the application, and
/// reads them as it deploys, so a change takes effect with the next deployment.
///
/// Which fields matter depends on the build pack: the three commands only for Nixpacks and Railpack, the publish
/// directory only for a static site they build, and the Dockerfile location only for a Dockerfile build.
public struct BuildSettings: Codable, Sendable, Hashable {
    public var installCommand: String?
    public var buildCommand: String?
    /// What the container runs as it starts.
    public var startCommand: String?
    /// The folder of the repository Coolify builds from, such as `/apps/web`. Coolify stores `/` for the root.
    public var baseDirectory: String?
    /// The folder a static build writes the site to, such as `/dist`.
    public var publishDirectory: String?
    /// Glob patterns, one per line. A push deploys only when it changes a file one of them matches.
    public var watchPaths: String?
    /// The Dockerfile's path, read from the base directory.
    public var dockerfileLocation: String?

    /// What Coolify stores for the repository's root. Coolify's `base_directory` column is not nullable, so the root
    /// is sent as `/`, never as an empty string, which reaches Laravel as `null`.
    public static let rootDirectory = "/"

    /// Where Coolify looks for a Dockerfile unless told otherwise.
    public static let defaultDockerfileLocation = "/Dockerfile"

    enum CodingKeys: String, CodingKey {
        case installCommand
        case buildCommand
        case startCommand
        case baseDirectory
        case publishDirectory
        case watchPaths
        case dockerfileLocation
    }

    public init(
        installCommand: String? = nil,
        buildCommand: String? = nil,
        startCommand: String? = nil,
        baseDirectory: String? = nil,
        publishDirectory: String? = nil,
        watchPaths: String? = nil,
        dockerfileLocation: String? = nil
    ) {
        self.installCommand = installCommand
        self.buildCommand = buildCommand
        self.startCommand = startCommand
        self.baseDirectory = baseDirectory
        self.publishDirectory = publishDirectory
        self.watchPaths = watchPaths
        self.dockerfileLocation = dockerfileLocation
    }

    /// Reads the flat fields from an application's own JSON object.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        installCommand = container.flexString(.installCommand)
        buildCommand = container.flexString(.buildCommand)
        startCommand = container.flexString(.startCommand)
        baseDirectory = container.flexString(.baseDirectory)
        publishDirectory = container.flexString(.publishDirectory)
        watchPaths = container.flexString(.watchPaths)
        dockerfileLocation = container.flexString(.dockerfileLocation)
    }

    /// Writes every field that has a value, flat into the update's own object. An empty command, publish directory,
    /// or set of watch paths clears it. An empty base directory goes as the root.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(installCommand, forKey: .installCommand)
        try container.encodeIfPresent(buildCommand, forKey: .buildCommand)
        try container.encodeIfPresent(startCommand, forKey: .startCommand)
        try container.encodeIfPresent(
            baseDirectory.map { $0.nonEmpty ?? Self.rootDirectory }, forKey: .baseDirectory)
        try container.encodeIfPresent(publishDirectory, forKey: .publishDirectory)
        try container.encodeIfPresent(watchPaths, forKey: .watchPaths)
        try container.encodeIfPresent(dockerfileLocation, forKey: .dockerfileLocation)
    }

    public var isEmpty: Bool {
        self == Self()
    }

    /// Whether a change reaches the app only with its next deployment. Watch paths do not: Coolify reads them as each
    /// push arrives.
    public var needsRedeploy: Bool {
        var build = self
        build.watchPaths = nil
        return !build.isEmpty
    }

    // MARK: Coolify's rules

    /// Whether Coolify's API takes the text as an install, build, or start command: words, spaces, `&&`, `||`, and
    /// quoted spans, up to 1,000 characters.
    ///
    /// This is Coolify's `SHELL_SAFE_COMMAND_PATTERN`. Outside quotes it refuses `;`, `|`, `&`, `$`, `` ` ``, `(`, `)`,
    /// `<`, `>`, `\`, and line breaks. Inside double quotes it still refuses `$`, `` ` ``, and `\`. Single quotes take
    /// anything but a line break. Each alternative starts with its own character, so matching them atomically accepts
    /// the same commands, and keeps a long refused one from backtracking without end.
    ///
    /// Empty is refused here, though Coolify takes it as clearing the command, so check only text that is there.
    public static func isShellSafeCommand(_ text: String) -> Bool {
        text.unicodeScalars.count <= 1_000
            && text.range(
                of: #"\A(?>[ \t]+|&&|\|\||"[^"$`\\\n\r]*"|'[^'\n\r]*'|[a-zA-Z0-9._\-/=:@,+\[\]{}#%^~*?!]+)+\z"#,
                options: .regularExpression) != nil
    }

    /// Whether Coolify takes the text as a base or publish directory: `/`, or a path under it, up to 255 characters.
    public static func isDirectory(_ text: String) -> Bool {
        text.unicodeScalars.count <= 255
            && text.range(of: #"\A/[a-zA-Z0-9._\-/~@+]*\z"#, options: .regularExpression) != nil
    }

    /// Whether Coolify takes the text as a file's path, such as `/Dockerfile`, up to 255 characters.
    public static func isFilePath(_ text: String) -> Bool {
        text.unicodeScalars.count <= 255
            && text.range(of: #"\A/[a-zA-Z0-9._\-/~@+]+\z"#, options: .regularExpression) != nil
    }

    /// A path the way Coolify's own form writes it: trimmed, with a leading `/` and no trailing one. Empty stays
    /// empty.
    public static func normalizedPath(_ text: String) -> String {
        var path = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return "" }
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path.hasPrefix("/") ? path : "/" + path
    }

    /// Watch paths the way Coolify stores them: one trimmed pattern per line, empty lines dropped, and no leading
    /// `/`, which Coolify strips, after the `!` of a negated pattern too. Coolify keeps a bare `!`, and so does this.
    public static func normalizedWatchPaths(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            var pattern = line.trimmingCharacters(in: .whitespaces)
            let negated = pattern.hasPrefix("!")
            if negated { pattern = pattern.dropFirst().trimmingCharacters(in: .whitespaces) }
            while pattern.hasPrefix("/") { pattern.removeFirst() }
            if negated { return "!" + pattern }
            return pattern.isEmpty ? nil : pattern
        }
        .joined(separator: "\n")
    }
}
