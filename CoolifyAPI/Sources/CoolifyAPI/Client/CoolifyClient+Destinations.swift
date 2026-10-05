import Foundation

extension CoolifyClient {
    /// Creates a Docker network destination on a server. A nil name or type stays out of the body.
    ///
    /// Coolify answers 409 when that network already exists, and 422 for a key it does not expect.
    public func createDestination(_ draft: DestinationDraft, onServer serverUUID: String) async throws -> Destination {
        try await post(
            "servers/\(CoolifyURL.encodePathComponent(serverUUID))/destinations",
            body: draft
        )
    }

    /// Renames a destination. The network cannot be changed, so the body is only the name.
    public func renameDestination(_ uuid: String, name: String) async throws -> Destination {
        try await patch(
            "destinations/\(CoolifyURL.encodePathComponent(uuid))",
            body: DestinationName(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        )
    }

    /// Deletes an unused destination. Coolify answers 409 when a resource still uses it.
    public func deleteDestination(_ uuid: String) async throws {
        _ = try await acknowledge(
            "DELETE",
            path: "destinations/\(CoolifyURL.encodePathComponent(uuid))"
        )
    }
}

/// A rename. The network is not a field Coolify accepts on this route.
private struct DestinationName: Encodable {
    var name: String
}
