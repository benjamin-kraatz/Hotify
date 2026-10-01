import CoolifyAPI
import Foundation

/// One resource's settings as the Settings tab edits them. The tab keeps the loaded copy and the edited one, and
/// sends Coolify only the fields that differ.
struct ResourceConfiguration: Hashable {
    var kind: ResourceKind
    var name: String
    var description: String
    /// An application's own addresses, one per row. Unused when the domains belong to containers.
    var domains: [String] = []
    var redirect: DomainRedirect = .both
    var forcesHTTPS = true
    /// The domains of each container of a service, or of each service in a Docker Compose application.
    var containers: [ContainerDomains] = []
    /// Whether the domains belong to containers rather than to the resource as a whole.
    var hasContainerDomains = false
    /// `nil` for a service, whose health checks live in its compose file.
    var healthCheck: HealthCheck?
    var isPublic = false
    var publicPort: Int?
}

/// The addresses of one container or compose service.
struct ContainerDomains: Identifiable, Hashable {
    /// The name in the compose file, which Coolify matches the update by.
    var name: String
    var label: String
    var domains: [String]

    var id: String { name }
}

extension ResourceConfiguration {
    init(application: Application) {
        kind = .application
        name = application.name
        description = application.description ?? ""
        redirect = application.redirect ?? .both
        forcesHTTPS = application.settings?.isForceHTTPSEnabled ?? true
        healthCheck = Self.cleaned(application.healthCheck)
        if application.isDockerCompose {
            hasContainerDomains = true
            containers = (application.dockerComposeDomains ?? [:])
                .map { ContainerDomains(name: $0.key, label: $0.key, domains: Self.split($0.value)) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } else {
            domains = Self.split(application.fqdn)
        }
    }

    init(database: Database) {
        kind = .database
        name = database.name ?? ""
        description = database.description ?? ""
        healthCheck = Self.cleaned(database.healthCheck)
        isPublic = database.isPublic ?? false
        publicPort = database.publicPort
    }

    /// Only the containers that can take a domain. Coolify lists a service's databases apart, and they have none.
    init(service: Service) {
        kind = .service
        name = service.name
        description = service.description ?? ""
        hasContainerDomains = true
        containers = (service.applications ?? []).map { container in
            ContainerDomains(
                name: container.name,
                label: container.humanName ?? container.name,
                domains: Self.split(container.fqdn)
            )
        }
    }

    /// The check with empty text fields as `nil`, which is how the form stores a field left empty. Otherwise
    /// typing into a field and clearing it again would count as a change.
    private static func cleaned(_ check: HealthCheck?) -> HealthCheck {
        var check = check ?? HealthCheck()
        for field: WritableKeyPath<HealthCheck, String?> in [
            \.command, \.method, \.scheme, \.host, \.path, \.responseText,
        ] where check[keyPath: field]?.isEmpty == true {
            check[keyPath: field] = nil
        }
        return check
    }

    /// Coolify keeps several addresses in one comma-separated string.
    static func split(_ text: String?) -> [String] {
        (text ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// The rows as Coolify takes them: trimmed, empty rows dropped, joined by commas.
    static func joined(_ domains: [String]) -> String {
        domains.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ",")
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedDescription: String { description.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: Changes

    /// What changed since `saved`, as an application update. `force` takes domains another resource already uses.
    func applicationUpdate(from saved: Self, force: Bool) -> ApplicationUpdate {
        var update = ApplicationUpdate()
        if trimmedName != saved.trimmedName { update.name = trimmedName }
        if trimmedDescription != saved.trimmedDescription { update.description = trimmedDescription }
        if hasContainerDomains {
            // Coolify replaces the whole list, so every service goes along, changed or not.
            if containerChanges(from: saved) {
                update.dockerComposeDomains = containers.map {
                    ComposeDomain(name: $0.name, domain: Self.joined($0.domains))
                }
            }
        } else if Self.joined(domains) != Self.joined(saved.domains) {
            update.domains = Self.joined(domains)
        }
        if redirect != saved.redirect { update.redirect = redirect }
        if forcesHTTPS != saved.forcesHTTPS { update.isForceHTTPSEnabled = forcesHTTPS }
        update.healthCheck = healthCheckChanges(from: saved)
        if force, update.domains != nil || update.dockerComposeDomains != nil { update.forceDomainOverride = true }
        return update
    }

    func databaseUpdate(from saved: Self) -> DatabaseUpdate {
        var update = DatabaseUpdate()
        if trimmedName != saved.trimmedName { update.name = trimmedName }
        if trimmedDescription != saved.trimmedDescription { update.description = trimmedDescription }
        if isPublic != saved.isPublic {
            update.isPublic = isPublic
            // Coolify only starts the proxy when the port comes with the switch.
            if isPublic { update.publicPort = publicPort }
        } else if isPublic, publicPort != saved.publicPort {
            update.publicPort = publicPort
        }
        update.healthCheck = healthCheckChanges(from: saved)
        return update
    }

    /// Only the containers whose domains changed. Coolify leaves the others as they are.
    func serviceUpdate(from saved: Self, force: Bool) -> ServiceUpdate {
        var update = ServiceUpdate()
        if trimmedName != saved.trimmedName { update.name = trimmedName }
        if trimmedDescription != saved.trimmedDescription { update.description = trimmedDescription }
        let before = Dictionary(saved.containers.map { ($0.name, Self.joined($0.domains)) }) { first, _ in first }
        let changed = containers.filter { Self.joined($0.domains) != before[$0.name] }
        if !changed.isEmpty {
            update.urls = changed.map { ServiceDomain(name: $0.name, url: Self.joined($0.domains)) }
            if force { update.forceDomainOverride = true }
        }
        return update
    }

    /// The fields of the health check that changed, with the switch always along. `nil` when nothing changed.
    ///
    /// Coolify's web form takes values its API refuses, such as a command with quotes. Sending only what was edited
    /// keeps such a value from failing a save that never touched it.
    private func healthCheckChanges(from saved: Self) -> HealthCheck? {
        guard let check = healthCheck, let before = saved.healthCheck, check != before else { return nil }
        var changes = HealthCheck(isEnabled: check.isEnabled)
        if check.kind != before.kind { changes.kind = check.kind }
        for field: WritableKeyPath<HealthCheck, String?> in [\.command, \.method, \.scheme, \.host, \.path]
        where check[keyPath: field] != before[keyPath: field] {
            changes[keyPath: field] = check[keyPath: field]
        }
        // Empty clears the text. Coolify stores it as no text to match.
        if check.responseText != before.responseText { changes.responseText = check.responseText ?? "" }
        for field: WritableKeyPath<HealthCheck, Int?> in [
            \.port, \.returnCode, \.interval, \.timeout, \.retries, \.startPeriod,
        ] where check[keyPath: field] != before[keyPath: field] {
            changes[keyPath: field] = check[keyPath: field]
        }
        return changes
    }

    private func containerChanges(from saved: Self) -> Bool {
        containers.map { Self.joined($0.domains) } != saved.containers.map { Self.joined($0.domains) }
    }

    // MARK: Checks

    /// The first thing Coolify would refuse, worded for the person editing. Checked before saving, which spares a
    /// round trip and a "Validation failed." with the reason buried in a list.
    var problem: String? {
        if trimmedName.isEmpty {
            return "A name is required."
        }
        let addresses = hasContainerDomains ? containers.flatMap(\.domains) : domains
        if let bad = addresses.map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: {
            !$0.isEmpty && !Self.isWebAddress($0)
        }) {
            return "\(bad) isn't a web address. It needs http:// or https:// and a host."
        }
        if kind == .database, isPublic, publicPort == nil {
            return "Public access needs a port."
        }
        if let port = publicPort, !(1...65_535).contains(port) {
            return "A port is a number from 1 to 65535."
        }
        return healthCheck.flatMap { Self.problem(in: $0, kind: kind) }
    }

    static func isWebAddress(_ text: String) -> Bool {
        guard let components = URLComponents(string: text), let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https", let host = components.host, !host.isEmpty
        else { return false }
        return true
    }

    /// Coolify's own rules for the health check fields, from its API validation.
    private static func problem(in check: HealthCheck, kind: ResourceKind) -> String? {
        guard check.isEnabled else { return nil }
        if kind == .application {
            if check.kind == .cmd {
                let command = check.command?.trimmingCharacters(in: .whitespaces) ?? ""
                if command.isEmpty {
                    return "A command check needs a command."
                }
                if command.range(of: #"^[a-zA-Z0-9 \-_./:=@,+]+$"#, options: .regularExpression) == nil {
                    return "Coolify only runs plain commands: letters, digits, spaces, and - _ . / : = @ , +."
                }
            } else {
                if let path = check.path?.trimmingCharacters(in: .whitespaces), !path.isEmpty,
                    path.range(of: #"^[a-zA-Z0-9/\-_.~%,;]+$"#, options: .regularExpression) == nil
                {
                    return "The path may hold letters, digits, and / - _ . ~ % , ; only."
                }
                if let host = check.host?.trimmingCharacters(in: .whitespaces), !host.isEmpty,
                    host.range(of: #"^[a-zA-Z0-9.\-_]+$"#, options: .regularExpression) == nil
                {
                    return "The host is a name or address, such as localhost."
                }
                if let port = check.port, !(1...65_535).contains(port) {
                    return "The port is a number from 1 to 65535."
                }
            }
        }
        for (label, value, minimum) in [
            ("interval", check.interval, 1), ("timeout", check.timeout, 1), ("retries", check.retries, 1),
            ("start period", check.startPeriod, 0),
        ] {
            if let value, value < minimum {
                return "The \(label) needs to be at least \(minimum)."
            }
        }
        return nil
    }
}
