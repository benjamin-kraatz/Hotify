import Foundation

/// One independently synced instance. Deleted records remain so offline devices cannot restore them.
struct InstanceSyncRecord: Codable, Equatable {
    var id: UUID
    var name: String
    var baseURL: URL
    var modifiedAt: Date
    var revision: String
    var isDeleted: Bool

    /// Deletions win permanently for an ID. Adding the same server again creates a new ID.
    func merged(with other: Self) -> Self {
        if isDeleted != other.isDeleted { return isDeleted ? self : other }
        if modifiedAt != other.modifiedAt { return modifiedAt > other.modifiedAt ? self : other }
        return revision >= other.revision ? self : other
    }
}
