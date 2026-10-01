import CoolifyAPI
import Foundation

/// Why a provisioning step stopped, sorted by what the user can do about it.
enum ProvisioningProblem: Equatable {
    /// HTTP 403: the token works but lacks the `write` ability.
    case permission(String)
    /// HTTP 401: Coolify no longer accepts the token.
    case signedOut
    /// HTTP 409: another resource already answers on a domain this service asked for.
    case conflicts([DomainConflict])
    /// HTTP 404 on create: this instance has not loaded the template yet.
    case unknownTemplate(String)
    case message(String)

    init(_ error: Error, template: String? = nil) {
        guard let error = error as? CoolifyError else {
            self = .message(error.localizedDescription)
            return
        }
        if error.isForbidden {
            self = .permission(error.message)
        } else if error.isUnauthenticated {
            self = .signedOut
        } else if error.statusCode == 409, !error.conflicts.isEmpty {
            self = .conflicts(error.conflicts)
        } else if error.isNotFound, let template, error.message.localizedStandardContains("Service not found") {
            self = .unknownTemplate(template)
        } else {
            self = .message(error.summary)
        }
    }
}
