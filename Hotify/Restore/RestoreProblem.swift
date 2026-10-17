import CoolifyAPI
import Foundation

/// Turns a refused upload or start into words for the person restoring.
enum RestoreProblem {
    static func message(for error: Error, source: DatabaseImportSource?) -> String {
        guard let error = error as? CoolifyError else { return error.localizedDescription }
        switch error.statusCode {
        case 404:
            // Coolify 4.3 has no import routes, which answers the same as a database that is gone.
            return "This Coolify instance does not offer database imports. They need Coolify 4.4 or later. "
                + "If it does, the database may have been deleted."
        case 409:
            return "Another import, start, or restart of this database is in progress. Try again when it ends."
        case 403:
            if case .server = source {
                return "Importing from a path on the server needs an API token with the deploy permission. "
                    + "The S3 copy or an upload works with a write token."
            }
            return "This instance's API token cannot write. Give it the write permission in Coolify to restore."
        case 422:
            return error.summary
        case 501:
            return "Coolify cannot import into databases on Swarm servers yet."
        default:
            return error.summary
        }
    }
}
