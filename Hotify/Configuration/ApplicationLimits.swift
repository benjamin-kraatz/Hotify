import CoolifyAPI
import Foundation

/// An application's CPU and memory limits, as the Settings tab edits them. An empty field means no limit, which
/// Coolify stores as `0`.
///
/// Coolify also keeps a swap limit and a soft memory limit. The tab leaves those alone, but checks a new memory limit
/// against them, since Docker refuses to start a container whose limits contradict each other.
struct ApplicationLimits: Hashable {
    /// The units a memory limit is entered in. Coolify's own form also takes bytes and kilobytes, which the picker
    /// offers only when the loaded limit needs them.
    enum MemoryUnit: String, Hashable, CaseIterable {
        case bytes = "b"
        case kilobytes = "k"
        case megabytes = "m"
        case gigabytes = "g"

        var symbol: String {
            switch self {
            case .bytes: "B"
            case .kilobytes: "KB"
            case .megabytes: "MB"
            case .gigabytes: "GB"
            }
        }

        var scale: Int64 {
            switch self {
            case .bytes: 1
            case .kilobytes: 1_024
            case .megabytes: 1_048_576
            case .gigabytes: 1_073_741_824
            }
        }
    }

    /// CPUs as typed, such as `0.5`. Empty for no limit.
    var cpus = ""
    /// `nil` for no limit.
    var memory: Int?
    var memoryUnit = MemoryUnit.megabytes
    /// The limits as Coolify returned them. A value is only checked once it is edited, so one Coolify took some other
    /// way does not hold up a save that never touched it.
    private let loaded: ResourceLimits

    init(limits: ResourceLimits?) {
        loaded = limits ?? ResourceLimits()
        if let count = ResourceLimits.cpuCount(in: loaded.cpus), count == 0 {
            cpus = ""
        } else {
            cpus = loaded.cpus?.trimmingCharacters(in: .whitespaces) ?? ""
        }
        // Shown in the largest unit that holds it whole, so `1024m` reads as 1 GB. A size Docker would not read
        // shows as no limit, and stays as it is unless the field is edited.
        if let bytes = ResourceLimits.bytes(in: loaded.memory), bytes > 0 {
            let unit = MemoryUnit.allCases.last { bytes % $0.scale == 0 } ?? .bytes
            if let amount = Int(exactly: bytes / unit.scale) {
                memory = amount
                memoryUnit = unit
            }
        }
    }

    /// The soft limit Coolify keeps, such as `256m`. `nil` when there is none.
    var memoryReservation: String? { Self.setLimit(loaded.memoryReservation) }

    /// The limit on memory and swap together that Coolify keeps. `nil` when there is none.
    var memorySwap: String? { Self.setLimit(loaded.memorySwap) }

    /// The units to pick from: megabytes, gigabytes, and the one in use.
    var memoryUnits: [MemoryUnit] {
        MemoryUnit.allCases.filter { $0 == .megabytes || $0 == .gigabytes || $0 == memoryUnit }
    }

    /// The CPUs as Coolify takes them. A comma counts as the decimal point, which the iOS keypad types in many regions.
    var cpusValue: String {
        let text = cpus.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if text.isEmpty || ResourceLimits.cpuCount(in: text) == 0 { return ResourceLimits.none }
        return text
    }

    var memoryValue: String {
        guard let memory, memory > 0 else { return ResourceLimits.none }
        return "\(memory)\(memoryUnit.rawValue)"
    }

    /// What changed since `saved`. `nil` when nothing did.
    func changes(from saved: Self) -> ResourceLimits? {
        var changes = ResourceLimits()
        if cpusValue != saved.cpusValue { changes.cpus = cpusValue }
        if memoryValue != saved.memoryValue {
            changes.memory = memoryValue
            // Docker refuses a swap limit without a memory limit, so lifting one lifts the other.
            if memoryValue == ResourceLimits.none, saved.memorySwap != nil {
                changes.memorySwap = ResourceLimits.none
            }
        }
        return changes.isEmpty ? nil : changes
    }

    /// The first limit Coolify or Docker would refuse, by Docker's own rules. Only edited values are checked.
    var problem: String? {
        let original = Self(limits: loaded)
        if cpusValue != original.cpusValue {
            guard let count = ResourceLimits.cpuCount(in: cpusValue) else {
                return "CPUs are a number, such as 0.5 or 2."
            }
            if count > 0, count < 0.01 {
                return "Docker needs a CPU limit of at least 0.01."
            }
        }
        if memoryValue != original.memoryValue, memoryValue != ResourceLimits.none {
            guard let bytes = ResourceLimits.bytes(in: memoryValue) else {
                return "That memory limit is larger than Docker can count."
            }
            if bytes < 6 * MemoryUnit.megabytes.scale {
                return "Docker needs a memory limit of at least 6 MB."
            }
            if let reservation = memoryReservation, let floor = ResourceLimits.bytes(in: reservation), bytes < floor {
                return
                    "Coolify keeps a soft limit of \(reservation) for this app, so the memory limit needs to be at least that."
            }
            if let swap = memorySwap, let ceiling = ResourceLimits.bytes(in: swap), bytes > ceiling {
                return
                    "Coolify caps memory and swap together at \(swap) for this app, so the memory limit can't be higher."
            }
        }
        return nil
    }

    /// A limit that is actually set. A size of zero, an empty string, and a missing value all mean none.
    private static func setLimit(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty,
            ResourceLimits.bytes(in: text) != 0
        else { return nil }
        return text
    }
}
