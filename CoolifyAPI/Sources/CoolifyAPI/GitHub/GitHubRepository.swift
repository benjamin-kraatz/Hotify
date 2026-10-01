import Foundation

/// A repository on github.com. Arbitrary hosts are rejected so credentials only reach GitHub.
public struct GitHubRepository: Sendable, Hashable {
    public let owner: String
    public let name: String

    public init(_ repository: String) throws {
        var value = repository.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("git@github.com:") {
            value = String(value.dropFirst("git@github.com:".count))
        } else if value.contains("://") {
            guard let url = URL(string: value), url.host?.lowercased() == "github.com",
                ["https", "ssh"].contains(url.scheme?.lowercased() ?? ""),
                url.password == nil, url.query == nil, url.fragment == nil
            else { throw CoolifyError(message: "This picker supports repositories on github.com.") }
            value = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        if value.hasSuffix(".git") { value = String(value.dropLast(4)) }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        guard parts.count == 2,
            parts.allSatisfy({ part in
                !part.isEmpty && part != "." && part != ".."
                    && part.unicodeScalars.allSatisfy { allowed.contains($0) }
            })
        else { throw CoolifyError(message: "The application's GitHub repository could not be read.") }
        owner = String(parts[0])
        name = String(parts[1])
    }

    public var label: String { "\(owner)/\(name)" }
}
