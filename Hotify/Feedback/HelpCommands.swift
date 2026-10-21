import SwiftUI

/// The Help menu. Hotify has no help book, so the menu's place goes to reporting an issue and the project's page.
struct HelpCommands: Commands {
    @SwiftUI.Environment(\.openURL) private var openURL

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Report an Issue…") {
                openURL(IssueReport().url)
            }
            Button("Hotify on GitHub") {
                openURL(IssueReport.repository)
            }
        }
    }
}
