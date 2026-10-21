import Foundation

/// A new GitHub issue for Hotify, filled in with the build and the system it runs on. It only opens the browser:
/// nothing reaches GitHub until the person reads the draft and submits it.
struct IssueReport {
    /// The error the person saw, if they report from one.
    var error: String?
    var buildInfo: AppBuildInfo = .current
    var system: String = Self.currentSystem

    static let repository = URL(string: "https://github.com/benjamin-kraatz/Hotify")!

    var url: URL {
        var components = URLComponents(
            url: Self.repository.appending(path: "issues/new"), resolvingAgainstBaseURL: false)!
        // Encoded by hand: URLComponents leaves `+` and `&` as they are, and GitHub reads a `+` as a space.
        components.percentEncodedQuery = "body=" + Self.encode(body)
        return components.url!
    }

    var body: String {
        var sections = [
            "**What happened?**\n",
            "**What did you expect?**\n",
            "**Steps to reproduce**\n\n1. ",
        ]
        if let error = error?.trimmingCharacters(in: .whitespacesAndNewlines), !error.isEmpty {
            // Kept short, since GitHub turns away a new-issue link over about 8 KB.
            let quoted = String(error.prefix(1_000))
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { "> \($0)" }
                .joined(separator: "\n")
            sections.append("**Error shown**\n\n\(quoted)")
        }
        sections.append(
            """
            ---
            Hotify \(buildInfo.version) (\(buildInfo.build)), commit \(buildInfo.commit ?? "unavailable")
            \(system)
            Coolify version:

            <!-- Check this for anything private, such as a server's address, before you submit. -->
            """
        )
        return sections.joined(separator: "\n\n")
    }

    private static var currentSystem: String {
        let version = ProcessInfo.processInfo.operatingSystemVersionString
        #if os(macOS)
        return "macOS \(version)"
        #else
        return ProcessInfo.processInfo.isiOSAppOnMac ? "iOS app on macOS \(version)" : "iOS \(version)"
        #endif
    }

    private static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~")))
            ?? ""
    }
}
