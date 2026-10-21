import SwiftUI

/// A command worth one tap inside a container: a look at its processes, its disk, its environment.
struct TerminalSnippet: Identifiable, Hashable {
    var title: String
    var command: String

    var id: String { command }

    /// What people type first in a container. Each one works in a plain Alpine or Debian image.
    static let container: [TerminalSnippet] = [
        TerminalSnippet(title: "Processes", command: "ps aux"),
        TerminalSnippet(title: "Live Processes", command: "top"),
        TerminalSnippet(title: "Environment", command: "env | sort"),
        TerminalSnippet(title: "Disk Space", command: "df -h"),
        TerminalSnippet(title: "Listening Ports", command: "netstat -tln 2>/dev/null || ss -tln"),
        TerminalSnippet(title: "Operating System", command: "cat /etc/os-release"),
        TerminalSnippet(title: "Working Directory", command: "pwd && ls -la"),
    ]
}

/// The Run menu in the terminal's header: a snippet typed into the shell, with Return.
struct SnippetMenu: View {
    var snippets: [TerminalSnippet] = TerminalSnippet.container
    var onRun: (TerminalSnippet) -> Void

    var body: some View {
        Menu {
            ForEach(snippets) { snippet in
                Button {
                    onRun(snippet)
                } label: {
                    Text(snippet.title)
                    Text(snippet.command)
                }
            }
        } label: {
            Label("Run", systemImage: "terminal")
        }
        .help("Type a common command into the shell")
    }
}

#Preview {
    SnippetMenu(onRun: { _ in })
        .padding()
}
