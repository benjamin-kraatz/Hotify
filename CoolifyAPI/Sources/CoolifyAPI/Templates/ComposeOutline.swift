import Foundation

/// What a template's compose file runs and asks for, read without a YAML parser.
///
/// Coolify writes every template in the same shape: `services:` at the top level, each container two spaces in, its
/// keys four spaces in. Reading those lines is enough to name the containers before anything is created.
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
        for line in compose.split(separator: "\n", omittingEmptySubsequences: true) {
            let indent = line.prefix { $0 == " " }.count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if indent == 0 {
                inServices = trimmed == "services:"
                continue
            }
            guard inServices else { continue }
            if indent == 2, trimmed.hasSuffix(":") {
                result.append(Container(name: unquote(String(trimmed.dropLast()))))
            } else if indent == 4, trimmed.hasPrefix("image:"), !result.isEmpty {
                let image = unquote(trimmed.dropFirst("image:".count).trimmingCharacters(in: .whitespaces))
                result[result.count - 1].image = image.isEmpty ? nil : image
            }
        }
        return result
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
