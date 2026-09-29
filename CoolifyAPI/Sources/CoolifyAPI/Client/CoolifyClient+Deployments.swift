import Foundation

extension CoolifyClient {
    /// Deployments that are queued or in progress, including preview deployments.
    public func runningDeployments() async throws -> [Deployment] {
        try await getList("deployments")
    }

    public func deployment(_ uuid: String) async throws -> Deployment {
        try await get("deployments/\(CoolifyURL.encodePathComponent(uuid))")
    }

    public func applicationDeployments(
        _ uuid: String,
        skip: Int = 0,
        take: Int = 10
    ) async throws -> DeploymentPage {
        try await get(
            "deployments/applications/\(CoolifyURL.encodePathComponent(uuid))",
            query: [
                URLQueryItem(name: "skip", value: String(max(0, skip))),
                URLQueryItem(name: "take", value: String(max(1, take))),
            ]
        )
    }

    /// Preview rows from one page of application deployment history.
    ///
    /// The history endpoint accepts `skip` and `take` only. It does not filter by pull request, so a page of production deploys can hide previews.
    public func previewDeployments(
        forApplication uuid: String,
        skip: Int = 0,
        take: Int = 50
    ) async throws -> [Deployment] {
        let page = try await applicationDeployments(uuid, skip: skip, take: take)
        return page.deployments.filter(\.isPreview)
    }

    public func cancelDeployment(_ uuid: String) async throws -> QueuedAction {
        try await post("deployments/\(CoolifyURL.encodePathComponent(uuid))/cancel")
    }

    public func deploy(
        uuid: String? = nil,
        tag: String? = nil,
        force: Bool = false,
        pullRequestID: Int? = nil,
        dockerTag: String? = nil
    ) async throws -> DeployResult {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "force", value: Self.flag(force)),
        ]
        if let uuid, !uuid.isEmpty {
            query.append(URLQueryItem(name: "uuid", value: uuid))
        }
        if let tag, !tag.isEmpty {
            query.append(URLQueryItem(name: "tag", value: tag))
        }
        if let pullRequestID {
            query.append(URLQueryItem(name: "pull_request_id", value: String(pullRequestID)))
        }
        if let dockerTag, !dockerTag.isEmpty {
            query.append(URLQueryItem(name: "docker_tag", value: dockerTag))
        }
        return try await post("deploy", query: query)
    }
}
