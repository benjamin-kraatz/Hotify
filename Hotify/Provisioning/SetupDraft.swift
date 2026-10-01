import CoolifyAPI
import Foundation

/// The addresses and settings of a service Coolify just created, as the user edits them before its first start.
struct SetupDraft: Hashable {
    var domains: [DomainDraft] = []
    /// Variables the template leaves to the user, such as a mail host.
    var settings: [VariableDraft] = []
    /// Passwords, users, and addresses Coolify generated. Shown by name only.
    var generated: [VariableDraft] = []

    init(domains: [DomainDraft] = [], settings: [VariableDraft] = [], generated: [VariableDraft] = []) {
        self.domains = domains
        self.settings = settings
        self.generated = generated
    }

    init(service: Service, variables: [EnvironmentVariable], outline: ComposeOutline) {
        domains = (service.applications ?? []).map { container in
            DomainDraft(
                container: container.name,
                label: container.humanName ?? container.name,
                image: container.image,
                original: container.fqdn ?? ""
            )
        }
        let required = outline.requiredKeys
        let defaults = Dictionary(
            outline.variables.compactMap { variable in variable.defaultValue.map { (variable.key, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        let drafts = variables.filter { !$0.isPreview }.map { variable in
            VariableDraft(
                key: variable.key,
                original: variable.value,
                isRequired: required.contains(variable.key),
                defaultValue: defaults[variable.key]
            )
        }
        settings = drafts.filter { !$0.isGenerated }
        generated = drafts.filter(\.isGenerated)
    }

    var changedDomains: [ServiceDomain] {
        domains.filter(\.isChanged).map { ServiceDomain(name: $0.container, url: $0.trimmed) }
    }

    var changedValues: [EnvironmentVariableValue] {
        settings.filter(\.isChanged).map { EnvironmentVariableValue(key: $0.key, value: $0.value) }
    }

    var hasChanges: Bool {
        !changedDomains.isEmpty || !changedValues.isEmpty
    }

    /// Required settings still empty. Compose refuses to start the service until they have a value.
    var missingKeys: [String] {
        settings.filter { $0.isRequired && $0.value.trimmingCharacters(in: .whitespaces).isEmpty }.map(\.key)
    }
}

/// The addresses of one container. Coolify keeps several in one comma-separated string.
struct DomainDraft: Identifiable, Hashable {
    /// The compose name, which Coolify matches the update by.
    var container: String
    var label: String
    var image: String?
    var original: String
    var value: String

    var id: String { container }

    init(container: String, label: String, image: String? = nil, original: String, value: String? = nil) {
        self.container = container
        self.label = label
        self.image = image
        self.original = original
        self.value = value ?? original
    }

    var trimmed: String {
        value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .joined(separator: ",")
    }

    var isChanged: Bool { trimmed != original }

    /// Coolify only fills in an address for a container that serves the web, so one without is internal.
    var isPublic: Bool { !original.isEmpty }
}

/// One environment variable of the new service.
struct VariableDraft: Identifiable, Hashable {
    var key: String
    /// `nil` when the token cannot read values. Such a variable is shown but left alone.
    var original: String?
    var value: String
    var isRequired = false
    var defaultValue: String?

    var id: String { key }

    init(key: String, original: String?, isRequired: Bool = false, defaultValue: String? = nil) {
        self.key = key
        self.original = original
        self.value = original ?? ""
        self.isRequired = isRequired
        self.defaultValue = defaultValue
    }

    var isHidden: Bool { original == nil }
    var isChanged: Bool { !isHidden && value != original }

    /// Coolify fills `SERVICE_*` variables itself: passwords, users, and each container's address.
    var isGenerated: Bool { key.hasPrefix("SERVICE_") }

    /// Typing into these should not show on screen.
    var isSecret: Bool {
        let upper = key.uppercased()
        return ["PASS", "SECRET", "TOKEN", "PRIVATE", "API_KEY", "_KEY"].contains { upper.contains($0) }
    }
}
