import CoolifyAPI
import SwiftUI

/// One card in the gallery, for a template or a database engine: its logo, name, and what it is for.
struct TemplateCard: View {
    var name: String
    var slogan: String
    var logoURL: URL?
    /// Drawn in place of a logo, for a card that stands for a kind of source rather than a product.
    var systemImage: String?

    @State private var isHovered = false
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.ember)
                        .symbolEffect(.bounce, value: isHovered && !reduceMotion)
                        .frame(width: 40, height: 40)
                        .background(
                            .ember.opacity(isHovered ? 0.2 : 0.12), in: .rect(cornerRadius: 10.4, style: .continuous))
                } else {
                    TemplateLogo(name: name, url: logoURL, size: 40)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.ember)
                    .opacity(isHovered ? 1 : 0)
                    .offset(x: isHovered || reduceMotion ? 0 : -4)
                    .padding(.top, 4)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(slogan)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2, reservesSpace: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(isHovered ? 0.07 : 0.045), in: .rect(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.ember.opacity(isHovered ? 0.45 : 0), lineWidth: 1)
        }
        .scaleEffect(isHovered && !reduceMotion ? 1.015 : 1)
        .contentShape(.rect(cornerRadius: 16))
        .onHover { isHovered = $0 }
        .animation(.snappy(duration: 0.2), value: isHovered)
        .accessibilityElement(children: .combine)
        .accessibilityHint(slogan)
    }
}

extension TemplateCard {
    init(template: ServiceTemplate, instanceRoot: URL?) {
        self.init(
            name: template.displayName, slogan: template.slogan, logoURL: template.logoURL(instanceRoot: instanceRoot))
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
        TemplateCard(
            template: ServiceTemplate(
                slug: "ghost", slogan: "Ghost is a content management system (CMS) and blogging platform."),
            instanceRoot: nil)
        TemplateCard(
            template: ServiceTemplate(slug: "uptime-kuma", slogan: "A fancy self-hosted monitoring tool."),
            instanceRoot: nil)
        TemplateCard(name: "PostgreSQL", slogan: "The relational database most apps expect.", logoURL: nil)
    }
    .padding(24)
    .frame(width: 760)
}
