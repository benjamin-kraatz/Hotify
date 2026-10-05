import Foundation

/// The dashboard's filters: which states, kinds, and tags the list shows.
///
/// An empty set lets everything through. Picks within a set widen it, so Running and Stopped together show both,
/// and the sets narrow each other. A tag filter keeps a resource only when one of its loaded tags is picked. A
/// resource with no loaded tags does not match.
struct ResourceFilter: Hashable {
    var states: Set<ResourceStateFilter> = []
    var kinds: Set<ResourceKind> = []
    var tags: Set<String> = []

    var isActive: Bool { !states.isEmpty || !kinds.isEmpty || !tags.isEmpty }

    /// `heat` is the resource's heat as the list shows it, with an action or deployment in flight counted as warming.
    func includes(_ resource: ResourceSummary, heat: Heat) -> Bool {
        (kinds.isEmpty || kinds.contains(resource.kind))
            && (states.isEmpty || states.contains { $0.includes(heat) })
            && (tags.isEmpty || !Set(resource.tags).isDisjoint(with: tags))
    }
}

/// The states the dashboard filters by. They follow the heat summary's words: running, needs a look, and the rest.
enum ResourceStateFilter: CaseIterable, Identifiable, Hashable {
    case running
    case needsLook
    case stopped

    var id: Self { self }

    var title: String {
        switch self {
        case .running: "Running"
        case .needsLook: "Needs a Look"
        case .stopped: "Stopped"
        }
    }

    var systemImage: String {
        switch self {
        case .running: "flame.fill"
        case .needsLook: "exclamationmark.triangle"
        case .stopped: "flame"
        }
    }

    func includes(_ heat: Heat) -> Bool {
        switch self {
        case .running: heat == .lit
        case .needsLook: heat.needsAttention
        case .stopped: heat == .cold || heat == .unknown
        }
    }
}
