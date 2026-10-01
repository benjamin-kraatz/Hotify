import AppIntents
import WidgetKit

/// One moment of a Pinned Resources widget.
struct PinnedEntry: TimelineEntry {
    var date: Date
    var tiles: [PinTile]
    /// Nothing picked yet, or no instance saved in the app.
    var emptyReason: EmptyReason?

    enum EmptyReason {
        case noInstances
        case nothingPinned
    }
}

/// Reads the pinned resources and plans when to read them again.
struct PinnedProvider: AppIntentTimelineProvider {
    /// Something on its way up or down is worth another look soon. WidgetKit may stretch this, but it tries.
    private static let busyRefresh: TimeInterval = 60
    private static let quietRefresh: TimeInterval = 15 * 60

    func placeholder(in context: Context) -> PinnedEntry {
        PinnedEntry(date: .now, tiles: Array(PinTile.samples.prefix(Self.capacity(context.family))))
    }

    func snapshot(for configuration: PinnedResourcesIntent, in context: Context) async -> PinnedEntry {
        // The gallery shows what the widget looks like before anything is picked.
        if context.isPreview, configuration.resources?.isEmpty ?? true {
            return placeholder(in: context)
        }
        return await entries(for: configuration, family: context.family).first ?? placeholder(in: context)
    }

    func timeline(for configuration: PinnedResourcesIntent, in context: Context) async -> Timeline<PinnedEntry> {
        let entries = await entries(for: configuration, family: context.family)
        let isBusy = entries.first?.tiles.contains { $0.heat == .warming } ?? false
        let next = Date.now.addingTimeInterval(isBusy ? Self.busyRefresh : Self.quietRefresh)
        return Timeline(entries: entries, policy: .after(next))
    }

    private func entries(for configuration: PinnedResourcesIntent, family: WidgetFamily) async -> [PinnedEntry] {
        let now = Date.now
        guard !AppGroup.instances().isEmpty else {
            return [PinnedEntry(date: now, tiles: [], emptyReason: .noInstances)]
        }
        let picked = (configuration.resources ?? []).prefix(Self.capacity(family))
        let pins = picked.compactMap(\.pin)
        guard !pins.isEmpty else {
            return [PinnedEntry(date: now, tiles: [], emptyReason: .nothingPinned)]
        }
        let fresh = await ResourceProbe.read(pins, previous: WidgetLedger.load().readings)
        let ledger = WidgetLedger.update { ledger in
            ledger.absorb(fresh)
            return ledger
        }
        let names = Dictionary(picked.map { ($0.id, $0.name) }) { first, _ in first }
        func tiles(at date: Date) -> [PinTile] {
            pins.map { PinTile(pin: $0, fallbackName: names[$0.id] ?? "Resource", ledger: ledger, at: date) }
        }
        var entries = [PinnedEntry(date: now, tiles: tiles(at: now))]
        // An armed stop disarms on its own. Plan the moment it does.
        if let armed = ledger.armedStop, pins.contains(where: { $0.id == armed.pinID }), armed.until > now {
            entries.append(PinnedEntry(date: armed.until, tiles: tiles(at: armed.until)))
        }
        return entries
    }

    static func capacity(_ family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall: 1
        case .systemMedium: 4
        case .systemLarge, .systemExtraLarge: 6
        default: 1
        }
    }
}
