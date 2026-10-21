import SwiftUI

/// A quiet button beside an error that drafts a GitHub issue quoting it.
struct ReportErrorButton: View {
    var error: String

    var body: some View {
        Link(destination: IssueReport(error: error).url) {
            Image(systemName: "ladybug")
                .imageScale(.medium)
                .foregroundStyle(.secondary)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .help("Report this on GitHub")
        .accessibilityLabel("Report this on GitHub")
    }
}

#Preview {
    ReportErrorButton(error: "The server did not answer in time.")
        .padding()
}
