import CoolifyAPI
import SwiftUI

/// One template in the gallery: its logo, name, and what it is for.
struct TemplateCard: View {
    var template: ServiceTemplate
    var instanceRoot: URL?

    @State private var isHovered = false
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                TemplateLogo(name: template.displayName, url: template.logoURL(instanceRoot: instanceRoot), size: 40)
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.ember)
                    .opacity(isHovered ? 1 : 0)
                    .offset(x: isHovered || reduceMotion ? 0 : -4)
                    .padding(.top, 4)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(template.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(template.slogan)
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
        .accessibilityHint(template.slogan)
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
        TemplateCard(
            template: ServiceTemplate(
                slug: "ghost", slogan: "Ghost is a content management system (CMS) and blogging platform."))
        TemplateCard(template: ServiceTemplate(slug: "uptime-kuma", slogan: "A fancy self-hosted monitoring tool."))
        TemplateCard(template: ServiceTemplate(slug: "n8n", slogan: "Workflow automation for technical people."))
    }
    .padding(24)
    .frame(width: 760)
}
