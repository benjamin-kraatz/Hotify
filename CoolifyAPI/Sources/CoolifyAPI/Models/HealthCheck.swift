import Foundation

/// How Coolify decides a container is healthy. Coolify keeps these as flat `health_check_*` fields on the resource.
///
/// An application has every field. A database has only `isEnabled` and the four timings, and Coolify answers 422
/// to the rest, so `DatabaseUpdate` sends only those.
public struct HealthCheck: Codable, Sendable, Hashable {
    /// Whether Coolify probes over HTTP or runs a command inside the container.
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case http
        case cmd
    }

    public var isEnabled: Bool
    /// Applications only. `nil` reads as `http`, which is Coolify's default.
    public var kind: Kind?
    /// Run inside the container when `kind` is `cmd`.
    public var command: String?
    public var method: String?
    public var scheme: String?
    public var host: String?
    public var port: Int?
    public var path: String?
    /// The HTTP status a healthy container answers with.
    public var returnCode: Int?
    /// Text the response must contain. Empty accepts any.
    public var responseText: String?
    /// Seconds between checks.
    public var interval: Int?
    /// Seconds a check may take.
    public var timeout: Int?
    /// Failed checks in a row before the container counts as unhealthy.
    public var retries: Int?
    /// Seconds after start during which failures do not count.
    public var startPeriod: Int?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "healthCheckEnabled"
        case kind = "healthCheckType"
        case command = "healthCheckCommand"
        case method = "healthCheckMethod"
        case scheme = "healthCheckScheme"
        case host = "healthCheckHost"
        case port = "healthCheckPort"
        case path = "healthCheckPath"
        case returnCode = "healthCheckReturnCode"
        case responseText = "healthCheckResponseText"
        case interval = "healthCheckInterval"
        case timeout = "healthCheckTimeout"
        case retries = "healthCheckRetries"
        case startPeriod = "healthCheckStartPeriod"
    }

    public init(
        isEnabled: Bool = false,
        kind: Kind? = nil,
        command: String? = nil,
        method: String? = nil,
        scheme: String? = nil,
        host: String? = nil,
        port: Int? = nil,
        path: String? = nil,
        returnCode: Int? = nil,
        responseText: String? = nil,
        interval: Int? = nil,
        timeout: Int? = nil,
        retries: Int? = nil,
        startPeriod: Int? = nil
    ) {
        self.isEnabled = isEnabled
        self.kind = kind
        self.command = command
        self.method = method
        self.scheme = scheme
        self.host = host
        self.port = port
        self.path = path
        self.returnCode = returnCode
        self.responseText = responseText
        self.interval = interval
        self.timeout = timeout
        self.retries = retries
        self.startPeriod = startPeriod
    }

    /// Reads the flat fields from a resource's own JSON object. The port comes as a string, the timings as numbers.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = container.flexBool(.isEnabled) ?? false
        kind = container.flexString(.kind).flatMap(Kind.init(rawValue:))
        command = container.flexString(.command)
        method = container.flexString(.method)
        scheme = container.flexString(.scheme)
        host = container.flexString(.host)
        port = container.flexInt(.port)
        path = container.flexString(.path)
        returnCode = container.flexInt(.returnCode)
        responseText = container.flexString(.responseText)
        interval = container.flexInt(.interval)
        timeout = container.flexInt(.timeout)
        retries = container.flexInt(.retries)
        startPeriod = container.flexInt(.startPeriod)
    }

    /// Writes every field that has a value, flat into the update's own object.
    ///
    /// Coolify validates the path and host as non-empty strings, and Laravel turns an empty string into `null`, so
    /// an empty path or host stays out rather than fail with 422. The response text may be empty, which clears it.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encodeIfPresent(kind, forKey: .kind)
        try container.encodeIfPresent(command?.nonEmpty, forKey: .command)
        try container.encodeIfPresent(method?.nonEmpty, forKey: .method)
        try container.encodeIfPresent(scheme?.nonEmpty, forKey: .scheme)
        try container.encodeIfPresent(host?.nonEmpty, forKey: .host)
        try container.encodeIfPresent(port, forKey: .port)
        try container.encodeIfPresent(path?.nonEmpty, forKey: .path)
        try container.encodeIfPresent(returnCode, forKey: .returnCode)
        try container.encodeIfPresent(responseText, forKey: .responseText)
        try encodeTimings(into: &container)
    }

    /// Only what a database accepts: whether the check runs, and its timings.
    func encodeTimings(into container: inout KeyedEncodingContainer<CodingKeys>) throws {
        try container.encodeIfPresent(interval, forKey: .interval)
        try container.encodeIfPresent(timeout, forKey: .timeout)
        try container.encodeIfPresent(retries, forKey: .retries)
        try container.encodeIfPresent(startPeriod, forKey: .startPeriod)
    }
}

extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
