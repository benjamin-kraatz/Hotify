import Foundation

/// What a compose file runs and asks for, read without a YAML parser.
///
/// Coolify writes every template in the same shape: `services:` at the top level, each container one step in, its
/// keys one step further. Reading those lines is enough to name the containers before anything is created. The
/// step is whatever the file's first container uses, since a compose file someone wrote may indent by four.
///
/// This is an outline for display, never a parse to write back. A file in flow style or JSON reads as no containers.
public struct ComposeOutline: Sendable, Hashable {
    /// One container the compose file declares.
    public struct Container: Sendable, Hashable, Identifiable {
        public var name: String
        public var image: String?
        public var id: String { name }
    }

    /// A `${KEY}` reference the user may want to set. Coolify fills `SERVICE_*` references itself, so those are left out.
    public struct Variable: Sendable, Hashable, Identifiable {
        public var key: String
        /// The value after `:-` or `-`, if the reference has one.
        public var defaultValue: String?
        /// Written as `${KEY:?}` or `${KEY?}`: compose refuses to start while it is empty.
        public var isRequired: Bool
        public var id: String { key }
    }

    public var containers: [Container]
    public var variables: [Variable]

    public init(_ compose: String) {
        containers = Self.containers(in: compose)
        variables = Self.variables(in: compose)
    }

    public var requiredKeys: Set<String> {
        Set(variables.filter(\.isRequired).map(\.key))
    }

    private static func containers(in compose: String) -> [Container] {
        var result: [Container] = []
        var inServices = false
        /// How far in the containers sit, from the first line under `services:`.
        var containerIndent: Int?
        /// How far in the current container's keys sit, from its first key.
        var keyIndent: Int?
        for rawLine in compose.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            let line = rawLine.prefix { $0 != "\r" }
            let indent = line.prefix { $0 == " " }.count
            let trimmed = stripComment(line.trimmingCharacters(in: .whitespaces))
            if trimmed.isEmpty { continue }
            if indent == 0 {
                inServices = trimmed == "services:"
                containerIndent = nil
                keyIndent = nil
                continue
            }
            guard inServices else { continue }
            let level = containerIndent ?? indent
            containerIndent = level
            if indent == level {
                keyIndent = nil
                if let name = key(trimmed) {
                    result.append(Container(name: name))
                }
            } else if indent > level, !result.isEmpty {
                let keys = keyIndent ?? indent
                keyIndent = keys
                if indent == keys, trimmed.hasPrefix("image:") {
                    let image = unquote(trimmed.dropFirst("image:".count).trimmingCharacters(in: .whitespaces))
                    result[result.count - 1].image = image.isEmpty ? nil : image
                }
            }
        }
        return result
    }

    /// The key a mapping line opens, as in `web:` or `"web": {image: nginx}`. `nil` for a list item or a scalar.
    private static func key(_ line: String) -> String? {
        guard !line.hasPrefix("-") else { return nil }
        if line.hasSuffix(":") {
            return unquote(String(line.dropLast()))
        }
        guard let separator = line.range(of: ": ") else { return nil }
        return unquote(String(line[..<separator.lowerBound]))
    }

    /// The line without a trailing `# comment`. A `#` only starts a comment at the start or after a space.
    private static func stripComment(_ line: String) -> String {
        if line.hasPrefix("#") { return "" }
        guard let marker = line.range(of: " #") else { return line }
        return line[..<marker.lowerBound].trimmingCharacters(in: .whitespaces)
    }

    private static func variables(in compose: String) -> [Variable] {
        var order: [String] = []
        var found: [String: Variable] = [:]
        let pattern = /\$\{([A-Za-z_][A-Za-z0-9_]*)(?:(:?[-?])([^}]*))?\}/
        for match in compose.matches(of: pattern) {
            let key = String(match.output.1)
            guard !key.hasPrefix("SERVICE_") else { continue }
            let operation = match.output.2.map(String.init) ?? ""
            let fallback = match.output.3.map(String.init)
            let isRequired = operation.hasSuffix("?")
            let defaultValue = operation.hasSuffix("-") ? fallback : nil
            if var existing = found[key] {
                existing.isRequired = existing.isRequired || isRequired
                existing.defaultValue = existing.defaultValue ?? defaultValue
                found[key] = existing
            } else {
                order.append(key)
                found[key] = Variable(key: key, defaultValue: defaultValue, isRequired: isRequired)
            }
        }
        return order.compactMap { found[$0] }
    }

    private static func unquote(_ value: String) -> String {
        var value = value
        for quote in ["'", "\""] where value.count >= 2 && value.hasPrefix(quote) && value.hasSuffix(quote) {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }
}
