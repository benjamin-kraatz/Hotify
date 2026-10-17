import CoolifyAPI
import SwiftUI

/// One line in a catalog list: the logo, the name over one line of what it is for, and what kind it is.
/// A dense row instead of a card, so a column shows a dozen at a time.
struct CatalogRow: View {
    var entry: CatalogEntry
    var instanceRoot: URL?
    var isSelected = false

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            CatalogLogo(entry: entry, instanceRoot: instanceRoot, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(entry.slogan)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(entry.caption)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(background, in: .rect(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.ember.opacity(isSelected ? 0.35 : 0), lineWidth: 1)
        }
        .contentShape(.rect(cornerRadius: 10))
        .onHover { isHovered = $0 }
        .animation(.snappy(duration: 0.15), value: isHovered)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// A tinted pill for the open row, like the dashboard's, so the logos keep their colors.
    private var background: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(.ember.opacity(0.16)) }
        return isHovered ? AnyShapeStyle(.primary.opacity(0.05)) : AnyShapeStyle(.clear)
    }
}

/// An entry's mark: a template's or engine's logo, the compose mark, or an application source's symbol.
struct CatalogLogo: View {
    var entry: CatalogEntry
    var instanceRoot: URL?
    var size: CGFloat = 44

    var body: some View {
        switch entry {
        case .template(let template):
            TemplateLogo(name: template.displayName, url: template.logoURL(instanceRoot: instanceRoot), size: size)
        case .engine(let engine):
            TemplateLogo(name: engine.displayName, url: engine.logoURL(instanceRoot: instanceRoot), size: size)
        case .compose:
            ComposeMark(size: size)
        case .application(let source):
            Image(systemName: source.systemImage)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.ember)
                .frame(width: size, height: size)
                .background(.ember.opacity(0.12), in: .rect(cornerRadius: size * 0.26, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    VStack(spacing: 2) {
        CatalogRow(
            entry: .template(ServiceTemplate(slug: "n8n", slogan: "Workflow automation.", category: "automation")),
            isSelected: true)
        CatalogRow(entry: .engine(.postgresql))
        CatalogRow(entry: .compose)
        CatalogRow(entry: .application(.publicGit))
    }
    .padding()
    .frame(width: 520)
}
