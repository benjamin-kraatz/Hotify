import CoolifyAPI
import SwiftUI

/// How an application builds from its repository: the build pack, which only shows, the folders Coolify builds from,
/// Nixpacks' or Railpack's commands, and the watch paths that decide which pushes deploy.
struct BuildSection: View {
    @Binding var build: ApplicationBuild

    var body: some View {
        Section {
            LabeledContent("Build pack", value: build.buildPack.displayName)
            SettingField(title: "Base directory", text: $build.baseDirectory, prompt: BuildSettings.rootDirectory)
            if build.showsDockerfileLocation {
                SettingField(
                    title: "Dockerfile", text: $build.dockerfileLocation,
                    prompt: BuildSettings.defaultDockerfileLocation)
            }
            if let composeLocation = build.composeLocation {
                LabeledContent("Compose file") {
                    Text(verbatim: composeLocation)
                        .textSelection(.enabled)
                }
            }
            if build.showsPublishDirectory {
                SettingField(title: "Publish directory", text: $build.publishDirectory, prompt: "/dist")
            }
        } header: {
            Text("Build")
        } footer: {
            Text(footer)
        }

        if build.showsCommands {
            Section {
                CommandField(title: "Install", text: $build.installCommand, prompt: "npm ci")
                CommandField(title: "Build", text: $build.buildCommand, prompt: "npm run build")
                CommandField(title: "Start", text: $build.startCommand, prompt: "npm start")
            } header: {
                Label("Build Commands", systemImage: "server.rack")
            } footer: {
                let pack = build.buildPack.displayName
                Text(
                    "\(pack) runs the install and build commands on the server as it builds the image, and the start command in the container. Leave one empty for \(pack) to choose."
                )
            }
        }

        Section {
            CommandField(title: "Patterns", text: $build.watchPaths, prompt: "src/**", lines: 2...8)
        } header: {
            Text("Watch Paths")
        } footer: {
            Text(
                "One pattern per line, such as src/** or !docs/**. A push deploys only when it changes a matching file, and the last match wins. Empty deploys on every push."
            )
        }
    }

    private var footer: String {
        var text = "Coolify builds from this folder of the repository, which helps with monorepos."
        if build.showsDockerfileLocation {
            text += " The Dockerfile's path starts there."
        }
        if build.composeLocation != nil {
            text +=
                " The compose file's path starts there too. Change that path in Coolify, which reads the services from it."
        }
        if build.showsPublishDirectory {
            text += " The publish directory is where the build writes the site."
        }
        return text + " Changes take effect with the next deployment."
    }
}

#Preview("Nixpacks") {
    @Previewable @State var build = ApplicationBuild(
        buildPack: .nixpacks, isStatic: true,
        settings: BuildSettings(
            installCommand: "pnpm install --frozen-lockfile", buildCommand: "pnpm build", baseDirectory: "/apps/web",
            publishDirectory: "/dist", watchPaths: "apps/web/**\n!apps/web/docs/**"))
    Form {
        BuildSection(build: $build)
    }
    .formStyle(.grouped)
    .frame(width: 520, height: 720)
}

#Preview("Dockerfile") {
    @Previewable @State var build = ApplicationBuild(
        buildPack: .dockerfile, settings: BuildSettings(baseDirectory: "/", dockerfileLocation: "/Dockerfile"))
    Form {
        BuildSection(build: $build)
    }
    .formStyle(.grouped)
    .frame(width: 520, height: 420)
}

#Preview("Docker Compose") {
    @Previewable @State var build = ApplicationBuild(
        buildPack: .dockercompose, settings: BuildSettings(baseDirectory: "/"),
        composeLocation: "/docker-compose.yaml")
    Form {
        BuildSection(build: $build)
    }
    .formStyle(.grouped)
    .frame(width: 520, height: 420)
}
