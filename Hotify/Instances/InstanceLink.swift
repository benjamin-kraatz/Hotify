import Foundation

/// A link that opens one instance's dashboard: `hotify://instance/<instance>`. A notification about a whole server or
/// a burst of changes points here.
struct InstanceLink: Hashable {
    var instanceID: UUID

    var url: URL {
        URL(string: "\(ResourceLink.scheme)://instance/\(instanceID.uuidString)")!
    }

    init(instanceID: UUID) {
        self.instanceID = instanceID
    }

    init?(url: URL) {
        guard url.scheme == ResourceLink.scheme, url.host() == "instance",
            let id = url.pathComponents.filter({ $0 != "/" }).first.flatMap(UUID.init(uuidString:))
        else { return nil }
        instanceID = id
    }
}
