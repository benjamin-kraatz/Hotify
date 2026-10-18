import CoolifyAPI
import Foundation

/// Why Coolify refused a compose file, in words for the person who wrote it.
///
/// The message may quote the file, as Coolify's YAML errors do. It is shown on screen and goes nowhere else.
enum ComposeFailure {
    /// `nil` when the error is not about the compose file, so the caller words it as any other failure.
    static func message(for error: Error) -> String? {
        guard let error = error as? CoolifyError else { return nil }
        if let reasons = error.fieldErrors["docker_compose_raw"], !reasons.isEmpty {
            return "Coolify refused the compose file. " + reasons.map { sentence($0) }.joined(separator: " ")
        }
        // Coolify 4.4 parses the YAML before its own checks and lets a parse error escape as a bare 500.
        if error.statusCode == 500 {
            return
                "Coolify couldn't read the compose file, most likely because it isn't valid YAML. It didn't say where. Check the indentation, colons, and quotes."
        }
        return nil
    }

    private static func sentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last, !".!?".contains(last) else { return trimmed }
        return trimmed + "."
    }
}
