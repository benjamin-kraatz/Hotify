import CoolifyAPI

extension Service {
    /// The name to show. Coolify names a template service `<type>-<random>` unless someone renames it, so such a
    /// name gives way to the type. A name the user chose, such as one from Hotify's New Service, is kept.
    var displayName: String {
        guard let type = serviceType, !type.isEmpty else { return name.isEmpty ? uuid : name }
        guard !name.isEmpty, name != type else { return type }
        let suffix = name.hasPrefix("\(type)-") ? name.dropFirst(type.count + 1) : ""
        let isGenerated = suffix.count >= 10 && suffix.allSatisfy { $0.isLetter || $0.isNumber }
        return isGenerated ? type : name
    }
}
