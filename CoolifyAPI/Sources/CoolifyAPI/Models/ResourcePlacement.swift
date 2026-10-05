import Foundation

/// The body for `POST /applications|databases|services/{uuid}/move`.
///
/// Coolify 4.3 answers 422 to a key it does not expect, so this carries only the target environment.
public struct MoveResourceRequest: Encodable, Sendable, Hashable {
    public var environmentUUID: String

    public init(environmentUUID: String) {
        self.environmentUUID = environmentUUID
    }

    enum CodingKeys: String, CodingKey {
        // snake_case conversion of `environmentUUID` would split the acronym into `environment_u_u_i_d`.
        case environmentUUID = "environmentUuid"
    }
}

/// The body for `POST /applications|databases|services/{uuid}/clone`.
///
/// A nil or blank name stays out, and so does `clone_volumes` unless it is true. Coolify's default is false.
/// Coolify 4.3 answers 422 to a key it does not expect.
public struct CloneResourceRequest: Encodable, Sendable, Hashable {
    public var destinationUUID: String
    public var name: String?
    public var cloneVolumes: Bool?

    public init(destinationUUID: String, name: String? = nil, cloneVolumes: Bool? = nil) {
        self.destinationUUID = destinationUUID
        self.name = name
        self.cloneVolumes = cloneVolumes
    }

    enum CodingKeys: String, CodingKey {
        // snake_case conversion of `destinationUUID` would split the acronym into `destination_u_u_i_d`.
        case destinationUUID = "destinationUuid"
        case name
        case cloneVolumes
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(destinationUUID, forKey: .destinationUUID)
        try container.encodeIfPresent(name?.nonEmpty, forKey: .name)
        if cloneVolumes == true {
            try container.encode(true, forKey: .cloneVolumes)
        }
    }
}

/// The body for `POST /applications|databases|services/{uuid}/migrate`.
///
/// `migrate_volumes` is omitted when nil. Coolify's default is true, so an omitted flag still transfers volumes
/// when Coolify manages both servers. False has to be sent, or Coolify would copy them. Coolify 4.3 answers 422
/// to a key it does not expect.
public struct MigrateResourceRequest: Encodable, Sendable, Hashable {
    public var destinationUUID: String
    public var migrateVolumes: Bool?

    public init(destinationUUID: String, migrateVolumes: Bool? = nil) {
        self.destinationUUID = destinationUUID
        self.migrateVolumes = migrateVolumes
    }

    enum CodingKeys: String, CodingKey {
        case destinationUUID = "destinationUuid"
        case migrateVolumes
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(destinationUUID, forKey: .destinationUUID)
        try container.encodeIfPresent(migrateVolumes, forKey: .migrateVolumes)
    }
}

/// What Coolify answers after a move, clone, or migrate. A migrate may answer with only a message, or an empty body.
public struct PlacementResult: Decodable, Sendable, Hashable {
    public var message: String?
    public var uuid: String?
    public var projectUUID: String?
    public var environmentUUID: String?

    public init(
        message: String? = nil, uuid: String? = nil, projectUUID: String? = nil, environmentUUID: String? = nil
    ) {
        self.message = message
        self.uuid = uuid
        self.projectUUID = projectUUID
        self.environmentUUID = environmentUUID
    }

    enum CodingKeys: String, CodingKey {
        case message
        case uuid
        case projectUUID = "projectUuid"
        case environmentUUID = "environmentUuid"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = container.flexString(.message)
        uuid = container.flexString(.uuid)
        projectUUID = container.flexString(.projectUUID)
        environmentUUID = container.flexString(.environmentUUID)
    }
}
