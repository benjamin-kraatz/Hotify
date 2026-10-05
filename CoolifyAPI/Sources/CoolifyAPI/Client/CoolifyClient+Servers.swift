import Foundation

extension CoolifyClient {
    /// Creates a server. Nil fields stay out of the body. The response is the new uuid.
    public func createServer(_ draft: ServerDraft) async throws -> CreatedResource {
        try await post("servers", body: draft)
    }

    /// Updates a server's connection and capacity. Nil fields stay out of the body.
    ///
    /// Coolify 4.3 answers 422 when the body contains a key it does not expect.
    public func updateServer(_ uuid: String, _ update: ServerUpdate) async throws -> Server {
        try await patch("servers/\(CoolifyURL.encodePathComponent(uuid))", body: update)
    }

    /// Deletes a server. Coolify answers with a message.
    public func deleteServer(_ uuid: String) async throws -> QueuedAction {
        try await delete("servers/\(CoolifyURL.encodePathComponent(uuid))")
    }

    /// Stores a private key on the instance.
    ///
    /// The key is sent once in this request and is not kept by the client.
    public func createPrivateKey(_ draft: PrivateKeyDraft) async throws -> CreatedResource {
        try await post("security/keys", body: draft)
    }
}
