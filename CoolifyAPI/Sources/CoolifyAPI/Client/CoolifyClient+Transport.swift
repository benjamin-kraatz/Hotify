import Foundation

extension CoolifyClient {
    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        let (data, response) = try await send("GET", path: path, query: query)
        return try decode(T.self, from: data, response: response)
    }

    func getList<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> [T] {
        let (data, response) = try await send("GET", path: path, query: query)
        return try decodeList(T.self, from: data, response: response)
    }

    func post<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        let (data, response) = try await send("POST", path: path, query: query)
        return try decode(T.self, from: data, response: response)
    }

    func post<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        let (data, response) = try await send("POST", path: path, body: try CoolifyJSON.encoder().encode(body))
        return try decode(T.self, from: data, response: response)
    }

    func patch<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        let (data, response) = try await send("PATCH", path: path, body: try CoolifyJSON.encoder().encode(body))
        return try decode(T.self, from: data, response: response)
    }

    func put<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        let (data, response) = try await send("PUT", path: path, body: try CoolifyJSON.encoder().encode(body))
        return try decode(T.self, from: data, response: response)
    }

    /// A write whose body is only a message, or empty. Volume backup delete and run are documented that way.
    func acknowledge(_ method: String, path: String, body: Data? = nil) async throws -> QueuedAction {
        let (data, response) = try await send(method, path: path, body: body)
        guard !data.isEmpty else { return QueuedAction(message: nil, deploymentUUID: nil) }
        return try decode(QueuedAction.self, from: data, response: response)
    }

    func patchList<T: Decodable>(_ path: String, body: some Encodable) async throws -> [T] {
        let (data, response) = try await send("PATCH", path: path, body: try CoolifyJSON.encoder().encode(body))
        return try decodeList(T.self, from: data, response: response)
    }

    func delete<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        let (data, response) = try await send("DELETE", path: path, query: query)
        return try decode(T.self, from: data, response: response)
    }

    func logs(
        _ path: String,
        window: LogWindow,
        showTimestamps: Bool,
        extraQuery: [URLQueryItem] = []
    ) async throws -> String {
        let output: LogPayload = try await get(
            path,
            query: extraQuery + [
                URLQueryItem(name: "lines", value: window.queryValue),
                URLQueryItem(name: "show_timestamps", value: Self.flag(showTimestamps)),
            ]
        )
        return output.logs
    }

    /// `GET /version` and `GET /health` return `text/html`, not JSON.
    func text(_ path: String) async throws -> String {
        let (data, _) = try await send("GET", path: path)
        let value = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if let payload = try? CoolifyJSON.decoder().decode(LogPayload.self, from: data), payload.logs.isEmpty == false {
            return payload.logs
        }
        if value.hasPrefix("{"),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = object["message"] as? String
        {
            return message
        }
        return value
    }

    private func send(
        _ method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        let url = try makeURL(path: path, query: query)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        if method != "GET" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw CoolifyError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw CoolifyError.transport("Coolify did not return an HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw makeError(status: http.statusCode, data: data, headers: http)
        }
        return (data, http)
    }

    private func makeURL(path: String, query: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(url: apiBaseURL, resolvingAgainstBaseURL: false) else {
            throw CoolifyError.invalidInstanceURL("API address could not be read.")
        }
        let trimmedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        var basePath = components.path
        if basePath.hasSuffix("/") {
            basePath.removeLast()
        }
        components.path = basePath + "/" + trimmedPath
        let items = query.filter { $0.value != nil }
        components.queryItems = items.isEmpty ? nil : items
        guard let url = components.url else {
            throw CoolifyError.invalidInstanceURL("API address could not be built.")
        }
        return url
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, response: HTTPURLResponse) throws -> T {
        if data.isEmpty {
            throw CoolifyError(
                statusCode: response.statusCode,
                message: "Coolify returned an empty body."
            )
        }
        do {
            return try CoolifyJSON.decoder().decode(T.self, from: data)
        } catch {
            throw CoolifyError(
                statusCode: response.statusCode,
                message: "Coolify returned JSON the client could not read.",
                responseBody: Self.bodySnippet(data)
            )
        }
    }

    /// Coolify sometimes JSON-encodes a list as an object with numeric keys. Accept either shape.
    private func decodeList<T: Decodable>(_ type: T.Type, from data: Data, response: HTTPURLResponse) throws -> [T] {
        if let list = try? CoolifyJSON.decoder().decode([T].self, from: data) {
            return list
        }
        if let dictionary = try? CoolifyJSON.decoder().decode([String: T].self, from: data) {
            return dictionary.keys.sorted().map { dictionary[$0]! }
        }
        throw CoolifyError(
            statusCode: response.statusCode,
            message: "Coolify returned JSON the client could not read.",
            responseBody: Self.bodySnippet(data)
        )
    }

    private func makeError(status: Int, data: Data, headers: HTTPURLResponse) -> CoolifyError {
        let snippet = Self.bodySnippet(data)
        let parsed = try? CoolifyJSON.decoder().decode(ErrorPayload.self, from: data)
        let message = parsed?.message ?? snippet ?? "Coolify returned HTTP \(status)."
        let retryAfter = headers.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
        return CoolifyError(
            statusCode: status,
            message: message,
            fieldErrors: parsed?.errors ?? [:],
            retryAfter: retryAfter,
            responseBody: snippet,
            conflicts: parsed?.conflicts ?? []
        )
    }

    private static func bodySnippet(_ data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        let text = String(decoding: data.prefix(2_000), as: UTF8.self)
        return text.isEmpty ? nil : text
    }
}

private struct LogPayload: Decodable {
    var logs: String
}

/// Laravel validation errors are `{ field: [messages] }`, and some endpoints send a single string per field.
/// Service domain checks send a plain list of messages instead, which lands under the empty key.
private struct ErrorPayload: Decodable {
    var message: String?
    var errors: [String: [String]]?
    var conflicts: [DomainConflict]?

    enum CodingKeys: String, CodingKey {
        case message
        case errors
        case conflicts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = container.flexString(.message)
        if let keyed = try? container.decode([String: [String]].self, forKey: .errors) {
            errors = keyed
        } else if let single = try? container.decode([String: String].self, forKey: .errors) {
            errors = single.mapValues { [$0] }
        } else if let list = try? container.decode([String].self, forKey: .errors), !list.isEmpty {
            errors = ["": list]
        } else {
            errors = nil
        }
        conflicts = try? container.decodeIfPresent([DomainConflict].self, forKey: .conflicts)
    }
}
