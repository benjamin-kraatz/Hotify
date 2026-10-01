import AppIntents
import CoolifyAPI
import Foundation
import WidgetKit

/// One moment of a Needs Attention widget.
struct AttentionEntry: TimelineEntry {
    var date: Date
    /// What wants a look, most urgent first.
    var tiles: [PinTile]
    /// Instances that could not be read, as sentences.
    var problems: [String] = []
    var instanceCount: Int
    var checkedAt: Date?
    var relevance: TimelineEntryRelevance?

    var hasNoInstances: Bool { instanceCount == 0 }
    var isQuiet: Bool { tiles.isEmpty && problems.isEmpty }
}

/// Scans the watched instances and keeps what wants a look. The widget floats up in a Smart Stack while anything
/// does.
struct AttentionProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> AttentionEntry {
        AttentionEntry(
            date: .now, tiles: [PinTile.samples[4], PinTile.samples[2]], instanceCount: 2, checkedAt: .now)
    }

    func snapshot(for configuration: NeedsAttentionIntent, in context: Context) async -> AttentionEntry {
        if context.isPreview { return placeholder(in: context) }
        return await entry(for: configuration)
    }

    func timeline(for configuration: NeedsAttentionIntent, in context: Context) async -> Timeline<AttentionEntry> {
        let entry = await entry(for: configuration)
        // Something on its way up or down settles within minutes. Something unhealthy may stay so all day.
        let isBusy = entry.tiles.contains { $0.heat == .warming }
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(isBusy ? 60 : 15 * 60)))
    }

    private func entry(for configuration: NeedsAttentionIntent) async -> AttentionEntry {
        let saved = AppGroup.instances()
        let picked = Set((configuration.instances ?? []).map(\.id))
        let ids = saved.map(\.id).filter { picked.isEmpty || picked.contains($0) }
        guard !ids.isEmpty else { return AttentionEntry(date: .now, tiles: [], instanceCount: 0) }

        let scans = await withTaskGroup(of: (UUID, Result<InstanceScan, InstanceAccess.AccessError>).self) { group in
            for id in ids {
                group.addTask { (id, await InstanceScan.read(id)) }
            }
            var results: [(UUID, Result<InstanceScan, InstanceAccess.AccessError>)] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        let now = Date.now
        let before = WidgetLedger.load()
        var fresh: [String: ResourceReading] = [:]
        var problems: [String] = []
        for (id, result) in scans {
            switch result {
            case .success(let scan):
                for resource in scan.resources {
                    let pin = ResourcePin(instanceID: id, route: resource.route)
                    // Only what wants a look, or what a widget is still acting on, goes into the ledger.
                    guard
                        resource.heat(pendingAction: nil).needsAttention || before.transitions[pin.id] != nil
                            || before.failure(for: pin.id) != nil
                    else { continue }
                    fresh[pin.id] = ResourceReading(summary: resource, instanceName: scan.instance.name, checkedAt: now)
                }
            case .failure(let error):
                let name = saved.first { $0.id == id }?.name ?? ""
                problems.append(error.problem.message(instanceName: name))
            }
        }
        let ledger = WidgetLedger.update { ledger in
            ledger.absorb(fresh)
            return ledger
        }
        let tiles = fresh.keys.compactMap(ResourcePin.init(id:))
            .map { PinTile(pin: $0, fallbackName: "Resource", ledger: ledger, at: now) }
            .filter { $0.isAlert || $0.heat.needsAttention }
            .sorted(by: Self.urgency)
        let score: Float = tiles.isEmpty && problems.isEmpty ? 0 : Float(50 + tiles.count)
        return AttentionEntry(
            date: now, tiles: tiles, problems: problems.sorted(), instanceCount: ids.count,
            checkedAt: scans.contains { (try? $0.1.get()) != nil } ? now : nil,
            relevance: TimelineEntryRelevance(score: score))
    }

    /// Sick before busy, then by name.
    private static func urgency(_ lhs: PinTile, _ rhs: PinTile) -> Bool {
        let lhsSick = lhs.heat == .troubled || lhs.heat == .unknown
        let rhsSick = rhs.heat == .troubled || rhs.heat == .unknown
        if lhsSick != rhsSick { return lhsSick }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
