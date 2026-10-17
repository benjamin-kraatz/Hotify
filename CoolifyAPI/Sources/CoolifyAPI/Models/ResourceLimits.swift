import Foundation

/// The CPU and memory limits Coolify puts on an application's container. Coolify keeps them as flat `limits_*` fields
/// on the application, as strings in Docker's notation, where `0` means no limit.
///
/// Coolify writes them into the container's compose file as it deploys, so a change takes effect with the next
/// deployment. A Docker Compose application runs its own compose file as written, without them.
public struct ResourceLimits: Codable, Sendable, Hashable {
    /// How many CPUs the container may use, such as `0.5` or `2`.
    public var cpus: String?
    /// The most memory the container may use: a whole number and a unit of `b`, `k`, `m`, or `g`, such as `512m`.
    public var memory: String?
    /// Memory and swap together. `0` leaves swap to Docker, which allows as much again as `memory`.
    public var memorySwap: String?
    /// The soft limit Docker holds the container to when the server runs short of memory.
    public var memoryReservation: String?

    /// What Coolify stores for no limit, and what lifts one. An empty string would reach Laravel as `null`, which
    /// Coolify refuses for these fields.
    public static let none = "0"

    enum CodingKeys: String, CodingKey {
        case cpus = "limitsCpus"
        case memory = "limitsMemory"
        case memorySwap = "limitsMemorySwap"
        case memoryReservation = "limitsMemoryReservation"
    }

    public init(cpus: String? = nil, memory: String? = nil, memorySwap: String? = nil, memoryReservation: String? = nil)
    {
        self.cpus = cpus
        self.memory = memory
        self.memorySwap = memorySwap
        self.memoryReservation = memoryReservation
    }

    /// Reads the flat fields from an application's own JSON object.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cpus = container.flexString(.cpus)
        memory = container.flexString(.memory)
        memorySwap = container.flexString(.memorySwap)
        memoryReservation = container.flexString(.memoryReservation)
    }

    /// Writes every field that has a value, flat into the update's own object.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(cpus, forKey: .cpus)
        try container.encodeIfPresent(memory, forKey: .memory)
        try container.encodeIfPresent(memorySwap, forKey: .memorySwap)
        try container.encodeIfPresent(memoryReservation, forKey: .memoryReservation)
    }

    public var isEmpty: Bool {
        cpus == nil && memory == nil && memorySwap == nil && memoryReservation == nil
    }

    /// The bytes a size in Docker's notation stands for, such as `512m` or `1G`. `0` for no limit, and `nil` for
    /// text Docker would not read as a size, such as `-1` or `1.5g`.
    ///
    /// Coolify's own form only writes a number with a one-letter unit, but its API stores any string, so a trailing
    /// `b`, as in `512mb`, and a bare number of bytes are read too.
    public static func bytes(in text: String?) -> Int64? {
        let text = (text ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        guard let match = text.wholeMatch(of: /(\d+)(?:([kmg])b?|b)?/),
            let amount = Int64(match.1)
        else { return nil }
        let scale: Int64 =
            switch match.2.map(String.init) {
            case "k"?: 1_024
            case "m"?: 1_048_576
            case "g"?: 1_073_741_824
            default: 1
            }
        let (bytes, overflow) = amount.multipliedReportingOverflow(by: scale)
        return overflow ? nil : bytes
    }

    /// The CPUs a limit stands for, such as `0.5` or `2`. `0` for no limit, and `nil` for anything Coolify's own form
    /// refuses, which takes digits with at most one decimal point.
    public static func cpuCount(in text: String?) -> Double? {
        let text = (text ?? "").trimmingCharacters(in: .whitespaces)
        guard text.wholeMatch(of: /\d*\.?\d+/) != nil else { return nil }
        return Double(text)
    }
}
