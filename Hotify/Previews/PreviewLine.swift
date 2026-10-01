import Foundation

/// One pull request's preview, pieced together from the application's deployment history.
///
/// Coolify 4.3 has no route that lists an application's previews, so a preview is known by the deployments that
/// built it. Hotify fills in the title, branch, and address from GitHub and the application's settings.
struct PreviewLine: Identifiable, Hashable {
    var number: Int
    /// Newest first. Never empty.
    var deployments: [DeploymentLine]
    var title: String?
    var branch: String?
    var isDraft = false
    var url: URL?
    /// Removed from Hotify since its last deployment. Coolify keeps the history, so the app has to remember.
    var isRemoved = false
    /// A redeploy or removal Hotify sent that the history does not show yet.
    var work: PreviewWork?

    var id: Int { number }
    var latest: DeploymentLine { deployments[0] }

    /// A cancelled build leaves the previous one running, so it does not decide the state.
    private var deciding: DeploymentLine? {
        deployments.first { !$0.status.hasPrefix("cancelled") }
    }

    var state: PreviewState {
        if work == .removing || isRemoved {
            return .removed
        }
        if work == .redeploying {
            return .building
        }
        switch deciding?.status {
        case "finished": return .live
        case "in_progress", "queued": return .building
        case "failed": return .failed
        default: return .cancelled
        }
    }

    var heat: Heat {
        work == nil ? state.heat : .warming
    }

    var stateLabel: String {
        switch work {
        case .redeploying: "Queuing…"
        case .removing: "Removing…"
        case nil: state.label
        }
    }

    /// The PR title from GitHub, else the subject of the commit the preview last built.
    var headline: String {
        title ?? latest.message ?? "Pull request #\(number)"
    }

    /// The build to follow or cancel while the preview builds.
    var activeDeployment: DeploymentLine? {
        deployments.first { $0.status == "in_progress" || $0.status == "queued" }
    }
}

/// Something Hotify asked Coolify to do with a preview, shown until a poll catches up.
enum PreviewWork: Hashable {
    case redeploying
    case removing
}

/// Where a preview stands, by its newest build that was not cancelled.
enum PreviewState: Hashable, CaseIterable {
    case building
    case failed
    case live
    case cancelled
    case removed

    var heat: Heat {
        switch self {
        case .building: .warming
        case .failed: .troubled
        case .live: .lit
        case .cancelled, .removed: .cold
        }
    }

    var label: String {
        switch self {
        case .building: "Building"
        case .failed: "Failed"
        case .live: "Live"
        case .cancelled: "Cancelled"
        case .removed: "Removed"
        }
    }

    var systemImage: String {
        switch self {
        case .building: "hammer"
        case .failed: "exclamationmark.triangle"
        case .live: "flame.fill"
        case .cancelled: "xmark.circle"
        case .removed: "trash"
        }
    }
}

/// The chips above the preview board.
enum PreviewFilter: Hashable, CaseIterable, Identifiable {
    case all
    case live
    case building
    case failed
    case inactive

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .live: "Live"
        case .building: "Building"
        case .failed: "Failed"
        case .inactive: "Inactive"
        }
    }

    /// The flame a chip shows when it has previews in it.
    var heat: Heat {
        switch self {
        case .all, .live: .lit
        case .building: .warming
        case .failed: .troubled
        case .inactive: .cold
        }
    }

    func includes(_ preview: PreviewLine) -> Bool {
        switch self {
        case .all: true
        case .live: preview.state == .live
        case .building: preview.state == .building
        case .failed: preview.state == .failed
        case .inactive: preview.state == .cancelled || preview.state == .removed
        }
    }
}

extension PreviewLine {
    /// Groups preview deployments by pull request, newest activity first.
    ///
    /// `queued` holds builds Hotify just started. Each stands in until the history lists it, or for a short while,
    /// so a build Coolify dropped does not look like it is running forever.
    static func group(
        _ deployments: [DeploymentLine],
        queued: [DeploymentLine] = [],
        removed: [Int: Date] = [:],
        now: Date = .now
    ) -> [PreviewLine] {
        let known = Set(deployments.map(\.id))
        let pending = queued.filter { line in
            !known.contains(line.id) && (line.startedAt.map { now.timeIntervalSince($0) < 90 } ?? false)
        }
        var byNumber: [Int: [DeploymentLine]] = [:]
        for line in pending + deployments {
            guard let number = line.pullRequest else { continue }
            byNumber[number, default: []].append(line)
        }
        return
            byNumber
            .map { number, lines in
                let sorted = lines.sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
                var preview = PreviewLine(number: number, deployments: sorted)
                if let removedAt = removed[number] {
                    preview.isRemoved = (sorted[0].startedAt ?? .distantPast) < removedAt
                }
                return preview
            }
            .sorted {
                let left = $0.latest.startedAt ?? .distantPast
                let right = $1.latest.startedAt ?? .distantPast
                return left == right ? $0.number > $1.number : left > right
            }
    }
}
