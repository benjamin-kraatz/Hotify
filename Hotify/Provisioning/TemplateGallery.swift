import CoolifyAPI
import SwiftUI

/// Every one-click template, on shelves by what it is for, with a popular shelf first and search across all of them.
struct TemplateGallery: View {
    var shelves: [TemplateShelf]
    var instanceRoot: URL?
    var isLoading = false
    var loadError: String?
    var onRetry: () -> Void = {}
    var onSelect: (ServiceTemplate) -> Void = { _ in }

    @State private var query = ""
    @State private var shelf: TemplateCategory?
    #if os(macOS)
    @FocusState private var isSearchFocused: Bool
    #endif
    @SwiftUI.Environment(\.horizontalSizeClass) private var sizeClass

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    private var templates: [ServiceTemplate] { shelves.flatMap(\.templates) }
    private var total: Int { shelves.reduce(0) { $0 + $1.templates.count } }

    private var popular: [ServiceTemplate] {
        let bySlug = Dictionary(templates.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        return TemplateCategory.popular.compactMap { bySlug[$0] }
    }

    /// Search results, best match first. A picked shelf narrows them.
    private var results: [ServiceTemplate] {
        let pool = shelf.flatMap { picked in shelves.first { $0.category == picked }?.templates } ?? templates
        return pool.compactMap { template in template.searchScore(trimmedQuery).map { (template, $0) } }
            .sorted { $0.1 == $1.1 ? Self.byName($0.0, $1.0) : $0.1 < $1.1 }
            .map(\.0)
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: sizeClass == .compact ? 150 : 210, maximum: 340), spacing: 14)]
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                header
                #if os(macOS)
                if !shelves.isEmpty {
                    searchField
                }
                #endif
                if !shelves.isEmpty {
                    shelfPicker
                    content
                }
                footnote
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .overlay { emptyState }
        #if os(iOS)
        .searchable(text: $query, prompt: searchPrompt)
        #endif
        .animation(.snappy, value: shelf)
        .animation(.snappy, value: trimmedQuery.isEmpty)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("New service")
                .font(.display(.title2))
            Text(
                "Pick one of Coolify's one-click services. Hotify creates it on your server, lets you set it up, and starts it."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var searchPrompt: String {
        shelves.isEmpty ? "Search templates" : "Search \(total) templates"
    }

    #if os(macOS)
    /// A sheet has no window toolbar to hold a search field, so it sits on top of the gallery.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(searchPrompt, text: $query)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
            if !query.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { query = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.title3)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .well(cornerRadius: 12)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.ember.opacity(isSearchFocused ? 0.5 : 0), lineWidth: 1)
        }
        .animation(.snappy(duration: 0.2), value: isSearchFocused)
        .onAppear { isSearchFocused = true }
    }
    #endif

    private var shelfPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(nil, title: "All", systemImage: "circle.grid.3x3", count: total)
                ForEach(shelves) { entry in
                    chip(
                        entry.category, title: entry.category.title, systemImage: entry.category.systemImage,
                        count: entry.templates.count)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func chip(_ value: TemplateCategory?, title: String, systemImage: String, count: Int) -> some View {
        let isSelected = shelf == value
        return Button {
            shelf = value
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .imageScale(.small)
                Text(title)
                Text(count, format: .number)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.tertiary))
                    .monospacedDigit()
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? AnyShapeStyle(.ember) : AnyShapeStyle(.primary.opacity(0.06)), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue("\(count) templates")
    }

    @ViewBuilder
    private var content: some View {
        if !trimmedQuery.isEmpty {
            if !results.isEmpty {
                grid(results)
            }
        } else if let shelf, let entry = shelves.first(where: { $0.category == shelf }) {
            section(entry.category.title, systemImage: entry.category.systemImage, entry.templates)
        } else {
            if !popular.isEmpty {
                section("Popular", systemImage: "star.fill", popular)
            }
            ForEach(shelves) { entry in
                section(entry.category.title, systemImage: entry.category.systemImage, entry.templates)
            }
        }
    }

    private func section(_ title: String, systemImage: String, _ templates: [ServiceTemplate]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.title3.weight(.semibold))
                    .labelStyle(ShelfLabelStyle())
                Text(templates.count, format: .number)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            grid(templates)
        }
    }

    private func grid(_ templates: [ServiceTemplate]) -> some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(templates) { template in
                Button {
                    onSelect(template)
                } label: {
                    TemplateCard(template: template, instanceRoot: instanceRoot)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var footnote: some View {
        Text(
            "Templates come from Coolify's public catalog at cdn.coollabs.io, the same one your instance uses. Hotify sends no token there."
        )
        .font(.footnote)
        .foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
        .opacity(shelves.isEmpty ? 0 : 1)
    }

    @ViewBuilder
    private var emptyState: some View {
        if shelves.isEmpty, let loadError {
            ContentUnavailableView {
                Label {
                    Text("The catalog didn't load")
                } icon: {
                    FlameGlyph(heat: .troubled, height: 44)
                }
            } description: {
                Text(loadError)
            } actions: {
                Button("Try Again", action: onRetry)
                    .glassButton(prominent: true)
            }
        } else if shelves.isEmpty {
            VStack(spacing: 14) {
                FlameGlyph(heat: .warming, height: 44)
                Text("Fetching Coolify's catalog")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .opacity(isLoading ? 1 : 0)
        } else if !trimmedQuery.isEmpty, results.isEmpty {
            ContentUnavailableView.search(text: trimmedQuery)
        }
    }

    private static func byName(_ lhs: ServiceTemplate, _ rhs: ServiceTemplate) -> Bool {
        lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
    }
}

/// The shelf's symbol in ember beside its title.
private struct ShelfLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .foregroundStyle(.ember)
                .imageScale(.medium)
            configuration.title
        }
    }
}

#Preview {
    NavigationStack {
        TemplateGallery(
            shelves: TemplateShelf.group([
                ServiceTemplate(
                    slug: "ghost", slogan: "A content management system and blogging platform.", category: "cms"),
                ServiceTemplate(
                    slug: "n8n", slogan: "Workflow automation for technical people.", category: "automation"),
                ServiceTemplate(
                    slug: "uptime-kuma", slogan: "A fancy self-hosted monitoring tool.", category: "monitoring"),
                ServiceTemplate(
                    slug: "umami", slogan: "Simple, privacy-friendly website analytics.", category: "analytics"),
                ServiceTemplate(slug: "gitea-with-postgresql", slogan: "Painless self-hosted Git.", category: "git"),
            ])
        )
    }
    .frame(width: 820, height: 700)
}

#Preview("Loading") {
    NavigationStack {
        TemplateGallery(shelves: [], isLoading: true)
    }
    .frame(width: 820, height: 500)
}
