import Foundation

/// A private key Coolify holds, with its material. Only fetch this for one use, and don't keep it.
///
/// `privateKey` is `nil` when Coolify withholds it, which it does for a token without the `read:sensitive` or
/// `root` permission. The material never shows in `description`.
public struct PrivateKeyMaterial: Decodable, Sendable, CustomStringConvertible {
    public var uuid: String
    public var name: String?
    public var privateKey: String?

    enum CodingKeys: String, CodingKey {
        case uuid
        case name
        case privateKey
    }

    public init(uuid: String, name: String? = nil, privateKey: String? = nil) {
        self.uuid = uuid
        self.name = name
        self.privateKey = privateKey
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = container.flexString(.uuid) ?? ""
        name = container.flexString(.name)
        let material = container.flexString(.privateKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        privateKey = material?.isEmpty == false ? material : nil
    }

    public var description: String { "PrivateKeyMaterial(uuid: \(uuid))" }
}
