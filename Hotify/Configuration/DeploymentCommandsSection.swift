import CoolifyAPI
import SwiftUI

/// The commands Coolify runs on the server before and after each deployment of an application, each in a section
/// of its own. A Docker Compose application also names the service each one runs in.
///
/// They run in the app's container on the Coolify server, never on this device. The server symbol in each header
/// and the first words of each footer keep them apart from the Shortcut automations Hotify runs here.
struct DeploymentCommandsSection: View {
    @Binding var commands: ApplicationDeploymentCommands

    var body: some View {
        Section {
            CommandField(
                title: "Command", text: $commands.preDeployment, prompt: "php artisan migrate --force", lines: 1...6)
            if commands.namesContainers {
                ServiceField(name: $commands.preDeploymentContainer, services: commands.services)
            }
        } header: {
            Label("Before Each Deployment", systemImage: "server.rack")
        } footer: {
            Text(preFooter)
        }

        Section {
            CommandField(
                title: "Command", text: $commands.postDeployment, prompt: "php artisan optimize", lines: 1...6)
            if commands.namesContainers {
                ServiceField(name: $commands.postDeploymentContainer, services: commands.services)
            }
        } header: {
            Label("After Each Deployment", systemImage: "server.rack")
        } footer: {
            Text(postFooter)
        }
    }

    private var preFooter: String {
        var text =
            "Coolify runs this on its server, in the app's running container, before the new version starts. If it fails, so does the deployment. With nothing running yet, it's skipped."
        if commands.namesContainers {
            text += commands.preNeedsContainer ? Self.namingWarning("fails the deployment") : Self.naming
        }
        if commands.preDeployment.contains(where: \.isNewline) { text += Self.lines }
        return text
    }

    private var postFooter: String {
        var text =
            "Coolify runs this on its server too, in the new container once it's up. If it fails, the deployment still finishes, and its log shows the failure."
        if commands.namesContainers {
            text += commands.postNeedsContainer ? Self.namingWarning("doesn't run") : Self.naming
        }
        if commands.postDeployment.contains(where: \.isNewline) { text += Self.lines }
        return text
    }

    private static let naming = " Name the compose service it runs in, unless the app has one container."

    private static func namingWarning(_ outcome: String) -> String {
        " Name the compose service it runs in. Without one, it \(outcome) once the app has more than one container."
    }

    // Coolify replaces line breaks with spaces before it runs the command.
    private static let lines = " Line breaks become spaces, so chain steps with &&."
}

/// The compose service a deployment command runs in, typed or picked from the services Coolify knows by name.
private struct ServiceField: View {
    @Binding var name: String
    var services: [String]

    var body: some View {
        HStack(spacing: 8) {
            SettingField(title: "Service", text: $name, prompt: "web")
            if !services.isEmpty {
                Menu {
                    ForEach(services, id: \.self) { service in
                        Button(service) { name = service }
                    }
                } label: {
                    Label("Pick a service", systemImage: "list.bullet")
                        .labelStyle(.iconOnly)
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Pick one of the services Coolify knows")
            }
        }
    }
}

#Preview("One container") {
    @Previewable @State var commands = ApplicationDeploymentCommands(
        commands: DeploymentCommands(preDeployment: "php artisan migrate --force"))
    Form {
        DeploymentCommandsSection(commands: $commands)
    }
    .formStyle(.grouped)
    .frame(width: 520, height: 480)
}

#Preview("Docker Compose") {
    @Previewable @State var commands = ApplicationDeploymentCommands(
        commands: DeploymentCommands(
            preDeployment: "php artisan migrate --force", preDeploymentContainer: "app",
            postDeployment: "php artisan queue:restart"),
        namesContainers: true, services: ["app", "worker"])
    Form {
        DeploymentCommandsSection(commands: $commands)
    }
    .formStyle(.grouped)
    .frame(width: 520, height: 600)
}
