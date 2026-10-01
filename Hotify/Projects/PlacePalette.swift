import SwiftUI

/// The colors of the open instance's projects and environments, as the views that mark them read and change them.
///
/// The window hands one down for the selected instance. Reading a color from it inside `body` observes the store,
/// so a color picked on this device or another one shows at once.
struct PlacePalette {
    var colors: PlaceColors?
    var instanceID: UUID?

    /// Whether a color can be saved. Without an instance there is nothing to keep it for.
    var canEdit: Bool { colors != nil && instanceID != nil }

    func project(_ uuid: String?) -> PlaceTint? {
        tint(of: .project, uuid)
    }

    /// `uuid` is `nil` for an environment Coolify sent without one, which cannot hold a color.
    func environment(_ uuid: String?) -> PlaceTint? {
        tint(of: .environment, uuid)
    }

    func setProject(_ tint: PlaceTint?, for uuid: String) {
        set(tint, of: .project, uuid)
    }

    func setEnvironment(_ tint: PlaceTint?, for uuid: String) {
        set(tint, of: .environment, uuid)
    }

    private func tint(of kind: PlaceKind, _ uuid: String?) -> PlaceTint? {
        guard let colors, let instanceID, let uuid else { return nil }
        return colors.tint(of: kind, uuid, in: instanceID)
    }

    private func set(_ tint: PlaceTint?, of kind: PlaceKind, _ uuid: String) {
        guard let colors, let instanceID else { return }
        colors.setTint(tint, of: kind, uuid, in: instanceID)
    }
}

extension PlacePalette {
    /// A palette in memory, for previews.
    static func preview(
        projects: [String: PlaceTint] = [:], environments: [String: PlaceTint] = [:]
    ) -> PlacePalette {
        let palette = PlacePalette(colors: PlaceColors(defaults: nil, cloud: nil), instanceID: UUID())
        for (uuid, tint) in projects {
            palette.setProject(tint, for: uuid)
        }
        for (uuid, tint) in environments {
            palette.setEnvironment(tint, for: uuid)
        }
        return palette
    }
}

extension EnvironmentValues {
    @Entry var placePalette = PlacePalette()
}
