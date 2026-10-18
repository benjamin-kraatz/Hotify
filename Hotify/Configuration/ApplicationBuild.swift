import CoolifyAPI
import Foundation

/// How an application builds from its repository, as the Settings tab edits it. The fields follow Coolify's own form
/// for each build pack, and the build pack itself only shows.
struct ApplicationBuild: Hashable {
    var buildPack: ApplicationBuildPack
    /// Whether Nixpacks or Railpack builds a static site, served from the publish directory.
    var isStatic = false
    var installCommand = ""
    var buildCommand = ""
    var startCommand = ""
    var baseDirectory = ""
    var publishDirectory = ""
    /// Glob patterns, one per line.
    var watchPaths = ""
    var dockerfileLocation = ""
    /// The compose file's path, which only shows. Coolify reads the services and their domains from that file, so
    /// changing it belongs in Coolify, which loads the new file as it saves.
    var composeLocation: String?
    /// The settings as Coolify returned them. A value is only checked once it is edited, so one Coolify took some other
    /// way does not hold up a save that never touched it.
    private let loaded: BuildSettings

    /// `nil` for an application with nothing to build from a repository: a Docker image, or a Dockerfile Coolify
    /// keeps itself.
    init?(application: Application) {
        guard !application.isDockerImage, !application.buildsFromInlineDockerfile,
            let repository = application.gitRepository, !repository.isEmpty,
            let pack = application.buildPack.flatMap(ApplicationBuildPack.init(rawValue:))
        else { return nil }
        self.init(
            buildPack: pack,
            isStatic: application.settings?.isStatic ?? false,
            settings: application.build ?? BuildSettings(),
            composeLocation: application.isDockerCompose ? application.dockerComposeLocation : nil)
    }

    init(
        buildPack: ApplicationBuildPack, isStatic: Bool = false, settings: BuildSettings,
        composeLocation: String? = nil
    ) {
        self.buildPack = buildPack
        self.isStatic = isStatic
        self.composeLocation = composeLocation
        loaded = settings
        installCommand = settings.installCommand ?? ""
        buildCommand = settings.buildCommand ?? ""
        startCommand = settings.startCommand ?? ""
        baseDirectory = settings.baseDirectory ?? BuildSettings.rootDirectory
        publishDirectory = settings.publishDirectory ?? ""
        watchPaths = settings.watchPaths ?? ""
        dockerfileLocation = settings.dockerfileLocation ?? ""
    }

    // MARK: What shows

    /// Coolify only passes the three commands to Nixpacks and Railpack.
    var showsCommands: Bool { buildPack == .nixpacks || buildPack == .railpack }

    /// Coolify only serves the publish directory of a static site Nixpacks or Railpack builds. The static build pack
    /// serves the base directory.
    var showsPublishDirectory: Bool { showsCommands && isStatic }

    var showsDockerfileLocation: Bool { buildPack == .dockerfile }

    // MARK: Values

    /// The commands as Coolify stores them, which trims them.
    var installValue: String { installCommand.trimmingCharacters(in: .whitespacesAndNewlines) }
    var buildValue: String { buildCommand.trimmingCharacters(in: .whitespacesAndNewlines) }
    var startValue: String { startCommand.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The root when the field is empty, since Coolify keeps a base directory for every application.
    var baseDirectoryValue: String {
        let path = BuildSettings.normalizedPath(baseDirectory)
        return path.isEmpty ? BuildSettings.rootDirectory : path
    }

    /// Empty for none.
    var publishDirectoryValue: String { BuildSettings.normalizedPath(publishDirectory) }

    var watchPathsValue: String { BuildSettings.normalizedWatchPaths(watchPaths) }

    /// Coolify's default when the field is empty, which is what Coolify itself stores for an empty one.
    var dockerfileLocationValue: String {
        let path = BuildSettings.normalizedPath(dockerfileLocation)
        return path.isEmpty ? BuildSettings.defaultDockerfileLocation : path
    }

    // MARK: Changes

    /// What changed since `saved`. `nil` when nothing did.
    func changes(from saved: Self) -> BuildSettings? {
        var changes = BuildSettings()
        // An empty command clears it, and Nixpacks or Railpack picks one again.
        if installValue != saved.installValue { changes.installCommand = installValue }
        if buildValue != saved.buildValue { changes.buildCommand = buildValue }
        if startValue != saved.startValue { changes.startCommand = startValue }
        if baseDirectoryValue != saved.baseDirectoryValue { changes.baseDirectory = baseDirectoryValue }
        if publishDirectoryValue != saved.publishDirectoryValue { changes.publishDirectory = publishDirectoryValue }
        if watchPathsValue != saved.watchPathsValue { changes.watchPaths = watchPathsValue }
        if dockerfileLocationValue != saved.dockerfileLocationValue {
            changes.dockerfileLocation = dockerfileLocationValue
        }
        return changes.isEmpty ? nil : changes
    }

    /// The first value Coolify would refuse, by its own API rules. Only edited values are checked.
    var problem: String? {
        guard let edited = changes(from: Self(buildPack: buildPack, isStatic: isStatic, settings: loaded)) else {
            return nil
        }
        for (name, command) in [
            ("install command", edited.installCommand), ("build command", edited.buildCommand),
            ("start command", edited.startCommand),
        ] {
            guard let command, !command.isEmpty else { continue }
            if command.unicodeScalars.count > 1_000 {
                return "The \(name) can be up to 1,000 characters."
            }
            if !BuildSettings.isShellSafeCommand(command) {
                return
                    "Coolify refuses that \(name). It takes && and ||, but ; | $ ` < > ( ) \\ only inside single quotes, and no line breaks."
            }
        }
        for (name, directory) in [
            ("base directory", edited.baseDirectory), ("publish directory", edited.publishDirectory),
        ] {
            guard let directory, !directory.isEmpty, !BuildSettings.isDirectory(directory) else { continue }
            if directory.unicodeScalars.count > 255 {
                return "The \(name) can be up to 255 characters."
            }
            return "The \(name) is a folder such as /apps/web, of letters, digits, and . _ - / ~ @ + only."
        }
        if let location = edited.dockerfileLocation, !BuildSettings.isFilePath(location) {
            return "The Dockerfile is a path such as /Dockerfile, of letters, digits, and . _ - / ~ @ + only."
        }
        return nil
    }
}
