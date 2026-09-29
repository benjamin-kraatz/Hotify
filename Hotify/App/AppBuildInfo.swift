import Foundation

/// The app's public version and the source revision embedded when it was built.
struct AppBuildInfo {
    var version: String
    var build: String
    var commit: String?

    var shortCommit: String { commit.map { String($0.prefix(7)) } ?? "Unavailable" }

    var copyableDetails: String {
        """
        Hotify \(version) (\(build))
        Commit: \(commit ?? "Unavailable")
        """
    }

    static let current: AppBuildInfo = {
        let bundle = Bundle.main
        let metadata = bundle.url(forResource: "BuildInfo", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(SourceRevision.self, from: $0) }
        return AppBuildInfo(
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
            commit: metadata?.commit
        )
    }()

    private struct SourceRevision: Decodable {
        var commit: String
    }
}
