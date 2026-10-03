import Foundation

/// The images Coolify kept for an application, and the tag of the one it runs.
///
/// Coolify lists them with `docker images` on the server. The list is empty when the application was never built,
/// when the server can't be reached, or when the server keeps no images. It keeps 2 per application by default.
public struct RollbackImages: Decodable, Sendable, Hashable {
    /// `nil` when nothing runs, or when the running image is referenced by digest.
    public var current: String?
    public var images: [RollbackImage]

    public init(current: String? = nil, images: [RollbackImage] = []) {
        self.current = current
        self.images = images
    }

    enum CodingKeys: String, CodingKey { case current, images }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        current = container.flexString(.current)
        images = (try? container.decode([RollbackImage].self, forKey: .images)) ?? []
    }

    /// The images a rollback can go to, newest first, without Coolify's build and preview images. The running one
    /// stays in the list, marked current, so the list shows where the application is.
    public var targets: [RollbackImage] {
        let kept = images.filter { !$0.isHelper }.map { image in
            var image = image
            image.isCurrent = image.isCurrent || image.tag == current
            return image
        }
        return kept.enumerated().sorted { lhs, rhs in
            switch (lhs.element.createdAtDate, rhs.element.createdAtDate) {
            case (let left?, let right?) where left != right: left > right
            case (.some, nil): true
            case (nil, .some): false
            default: lhs.offset < rhs.offset
            }
        }.map(\.element)
    }
}
