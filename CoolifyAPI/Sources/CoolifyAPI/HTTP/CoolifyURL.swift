import Foundation

enum CoolifyURL {
    /// Turns an instance root, an `/api/v1` URL, or the MCP URL from Coolify's settings into the API base.
    static func apiBase(from instanceURL: URL) throws -> URL {
        guard var components = URLComponents(url: instanceURL, resolvingAgainstBaseURL: false) else {
            throw CoolifyError.invalidInstanceURL("Instance URL could not be read.")
        }
        guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw CoolifyError.invalidInstanceURL("Instance URL needs an http or https scheme.")
        }
        guard let host = components.host, !host.isEmpty else {
            throw CoolifyError.invalidInstanceURL("Instance URL needs a host.")
        }

        components.scheme = scheme
        components.host = host
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil

        var path = components.path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        if path == "/" {
            path = ""
        }
        if path == "/mcp" || path.hasSuffix("/mcp") {
            path.removeLast("/mcp".count)
            while path.hasSuffix("/") {
                path.removeLast()
            }
        }

        if path == "/api/v1" || path.hasSuffix("/api/v1") {
            // Already the API root.
        } else if path == "/api" || path.hasSuffix("/api") {
            path += "/v1"
        } else {
            path += "/api/v1"
        }
        components.path = path

        guard let url = components.url else {
            throw CoolifyError.invalidInstanceURL("Instance URL could not be turned into an API address.")
        }
        return url
    }

    static func encodePathComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
