import SwiftUI

/// A color the user gives a project or an environment, to pick it out at a glance. Coolify has no such field, so
/// Hotify keeps these itself.
///
/// It marks where something lives, never how it is doing. Status stays with `Heat` and the flames.
enum PlaceTint: String, CaseIterable, Identifiable, Hashable, Sendable {
    case red
    case orange
    case yellow
    case green
    case teal
    case blue
    case indigo
    case purple
    case pink
    case graphite

    var id: Self { self }

    var title: String {
        switch self {
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .teal: "Teal"
        case .blue: "Blue"
        case .indigo: "Indigo"
        case .purple: "Purple"
        case .pink: "Pink"
        case .graphite: "Graphite"
        }
    }

    /// System colors, which adjust to light and dark appearance and to Increase Contrast.
    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .graphite: .gray
        }
    }
}
