import Foundation

/// The project page the New Resource sheet opened from. The pickers start there instead of at the last placement.
struct PlacementHint: Hashable {
    var projectUUID: String
    /// The uuids of the project's resources. The server that runs most of them is the one picked.
    var resourceUUIDs: Set<String>
}
