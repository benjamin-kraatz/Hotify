import SwiftUI
import WidgetKit

/// Draws a Recent Deployments widget for its size.
struct RecentDeploymentsView: View {
    var entry: DeploymentsEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(for: .widget) {
                HeatBackdrop(
                    heats: entry.items.first.map { [$0.heat] } ?? [], tone: entry.items.first?.tone ?? .production)
            }
    }

    @ViewBuilder
    private var content: some View {
        if entry.hasNoInstances {
            DeploymentsMessage(title: "No instance yet", detail: "Add a Coolify instance in Hotify.")
        } else if entry.items.isEmpty {
            DeploymentsMessage(
                title: "No deployments yet",
                detail: entry.problems.first ?? "Nothing deployed on the applications this widget follows.")
        } else {
            switch family {
            case .systemSmall:
                DeploymentHero(item: entry.items[0])
            #if os(iOS)
            case .accessoryRectangular:
                DeploymentAccessory(item: entry.items[0])
            #endif
            case .systemMedium:
                DeploymentList(entry: entry, capacity: 3, showsHeader: false)
            default:
                DeploymentList(entry: entry, capacity: 6, showsHeader: true)
            }
        }
    }
}

/// A flame and two lines, for a widget with nothing to list.
struct DeploymentsMessage: View {
    var title: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            FlameGlyph(heat: .cold, height: 28)
            Spacer(minLength: 4)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// An application's name, and the pull request number in blue when the deploy built a preview.
struct DeploymentTitle: View {
    var item: DeploymentItem
    var font: Font = .subheadline.weight(.semibold)

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(item.applicationName)
                .font(font)
                .lineLimit(1)
            if let pullRequest = item.pullRequest {
                Text("#\(pullRequest)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.pilot)
                    .widgetAccentable()
            }
        }
    }
}

/// Deployed, failed, or deploying, and how long ago.
struct DeploymentWhen: View {
    var item: DeploymentItem
    var alignment: HorizontalAlignment = .trailing

    private var tint: AnyShapeStyle {
        switch item.heat {
        case .troubled, .warming: AnyShapeStyle(.glow)
        case .lit: AnyShapeStyle(item.tone.fill)
        case .cold, .unknown: AnyShapeStyle(.secondary)
        }
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(item.statusLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            if let date = item.shownDate {
                Text(
                    .currentDate, format: .reference(to: date, allowedFields: [.minute, .hour, .day], maxFieldCount: 1)
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .lineLimit(1)
    }
}

/// The small widget: the newest deployment, large.
struct DeploymentHero: View {
    var item: DeploymentItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                FlameGlyph(heat: item.heat, height: 36, tone: item.tone)
                    .widgetAccentable()
                Spacer(minLength: 4)
                DeploymentWhen(item: item)
            }
            Spacer(minLength: 4)
            DeploymentTitle(item: item, font: .display(.headline))
            Text(item.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(item.link)
    }
}

/// One deployment as a row.
struct DeploymentRow: View {
    var item: DeploymentItem

    var body: some View {
        HStack(spacing: 12) {
            FlameGlyph(heat: item.heat, height: 22, tone: item.tone)
                .widgetAccentable()
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                DeploymentTitle(item: item)
                Text(item.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            DeploymentWhen(item: item)
        }
        .frame(maxHeight: .infinity)
        .contentShape(.rect)
    }
}

/// The medium and large widgets: the newest deployments, one row each.
struct DeploymentList: View {
    var entry: DeploymentsEntry
    var capacity: Int
    var showsHeader: Bool

    private var shown: [DeploymentItem] { Array(entry.items.prefix(capacity)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsHeader {
                HStack(alignment: .firstTextBaseline) {
                    Text("Deployments")
                        .font(.display(.subheadline))
                    Spacer(minLength: 4)
                    Text(following)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .lineLimit(1)
            }
            ForEach(shown) { item in
                if let link = item.link {
                    Link(destination: link) { DeploymentRow(item: item) }
                        .frame(maxHeight: 46)
                } else {
                    DeploymentRow(item: item)
                        .frame(maxHeight: 46)
                }
            }
            if showsHeader, let problem = entry.problems.first {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.glow)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    /// Which applications the list covers. A list that picked for itself says it may be missing some.
    private var following: String {
        if let available = entry.available, available > entry.followed {
            return "\(entry.followed) of \(available) apps · edit to pick"
        }
        return entry.followed == 1 ? "1 app" : "\(entry.followed) apps"
    }
}

#if os(iOS)
/// The Lock Screen rectangle: the newest deployment.
struct DeploymentAccessory: View {
    var item: DeploymentItem

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                FlameGlyph(heat: item.heat, height: 14, tone: item.tone)
                    .widgetAccentable()
                DeploymentTitle(item: item, font: .headline)
            }
            Text(item.summary)
                .font(.subheadline)
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(item.statusLabel)
                if let date = item.shownDate {
                    Text(
                        .currentDate,
                        format: .reference(to: date, allowedFields: [.minute, .hour, .day], maxFieldCount: 1))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(item.link)
    }
}

#Preview("Lock Screen", as: .accessoryRectangular) {
    RecentDeploymentsWidget()
} timeline: {
    DeploymentsEntry(date: .now, items: DeploymentItem.samples, followed: 4, checkedAt: .now)
}
#endif

#Preview("Small", as: .systemSmall) {
    RecentDeploymentsWidget()
} timeline: {
    DeploymentsEntry(date: .now, items: DeploymentItem.samples, followed: 4, checkedAt: .now)
    DeploymentsEntry(date: .now, items: Array(DeploymentItem.samples.dropFirst()), followed: 4, checkedAt: .now)
}

#Preview("Medium", as: .systemMedium) {
    RecentDeploymentsWidget()
} timeline: {
    DeploymentsEntry(date: .now, items: DeploymentItem.samples, followed: 4, checkedAt: .now)
}

#Preview("Large", as: .systemLarge) {
    RecentDeploymentsWidget()
} timeline: {
    DeploymentsEntry(date: .now, items: DeploymentItem.samples, followed: 12, available: 19, checkedAt: .now)
}
