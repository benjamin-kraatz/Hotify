import Foundation

/// The Shortcuts app's documented URLs: `shortcuts://run-shortcut?name=…&input=text&text=…` runs a Shortcut by name
/// with text as its input, and the others open the app, a new Shortcut, or one by name.
enum ShortcutLink {
    /// Opens the Shortcuts app where it was.
    static let app = URL(string: "shortcuts://")!
    /// Opens the editor on a new Shortcut.
    static let create = URL(string: "shortcuts://create-shortcut")!

    /// What stays as it is in a query value. `URLComponents.queryItems` leaves `+`, `&`, `=`, and `?` alone, and a
    /// `+` reads as a space to many decoders, so a value is encoded with only unreserved characters left.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Runs the Shortcut called `name`, handing it `text`. `nil` for a name that is empty once trimmed.
    static func run(_ name: String, text: String) -> URL? {
        guard let name = trimmed(name) else { return nil }
        return url(host: "run-shortcut", [("name", name), ("input", "text"), ("text", text)])
    }

    /// Opens the Shortcut called `name` in the editor.
    static func open(_ name: String) -> URL? {
        guard let name = trimmed(name) else { return nil }
        return url(host: "open-shortcut", [("name", name)])
    }

    private static func trimmed(_ name: String) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private static func url(host: String, _ items: [(name: String, value: String)]) -> URL? {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = host
        components.percentEncodedQueryItems = items.map {
            URLQueryItem(name: $0.name, value: $0.value.addingPercentEncoding(withAllowedCharacters: unreserved))
        }
        return components.url
    }
}
