import CoolifyAPI
import SwiftUI

/// The New Resource sheet on iPhone: a search over everything, a row of scopes, and one dense list. A compose file is
/// a scope like a shelf, so it takes no room of its own. Choosing an entry pushes the screen that creates it.
struct CatalogGallery: View {
    var shelves: [TemplateShelf]
    var instanceRoot: URL?
    var isLoading = false
    var loadError: String?
    var onRetry: () -> Void = {}
    var onSelect: (CatalogEntry) -> Void = { _ in }

    @State private var query = ""
    @State private var scope = CatalogScope.popular

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    private var scopes: [CatalogScope] {
        [.popular, .yourOwn, .databases, .repositories, .all] + shelves.map { .shelf($0.category) }
    }

    private var entries: [CatalogEntry] {
        trimmedQuery.isEmpty ? scope.entries(in: shelves) : CatalogScope.search(trimmedQuery, in: shelves)
    }

    var body: some View {
        List {
            Section {
                ForEach(entries) { entry in
                    Button {
                        onSelect(entry)
                    } label: {
                        row(entry)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                header
            }
            if entries.isEmpty {
                emptyState
                    .listRowBackground(Color.clear)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if trimmedQuery.isEmpty {
                scopePicker
            }
        }
        .searchable(text: $query, prompt: "Templates, databases, sources")
        .animation(.snappy, value: scope)
        .animation(.snappy, value: trimmedQuery.isEmpty)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(trimmedQuery.isEmpty ? scope.title : "Results")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
            Text(trimmedQuery.isEmpty ? scope.count(in: shelves) : entries.count, format: .number)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
    }

    private func row(_ entry: CatalogEntry) -> some View {
        HStack(spacing: 12) {
            CatalogLogo(entry: entry, instanceRoot: instanceRoot, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(entry.slogan)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var scopePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(scopes) { entry in
                    chip(entry)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private func chip(_ value: CatalogScope) -> some View {
        let isSelected = scope == value
        return Button {
            scope = value
        } label: {
            Label(value.title, systemImage: value.systemImage)
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background(isSelected ? AnyShapeStyle(.ember) : AnyShapeStyle(.primary.opacity(0.08)), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var emptyState: some View {
        if !trimmedQuery.isEmpty {
            ContentUnavailableView.search(text: trimmedQuery)
        } else if scope.isTemplates, let loadError {
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
        } else if scope.isTemplates, isLoading {
            VStack(spacing: 14) {
                FlameGlyph(heat: .warming, height: 44)
                Text("Fetching Coolify's catalog")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 240)
        }
    }
}

#Preview {
    NavigationStack {
        CatalogGallery(
            shelves: TemplateShelf.group([
                ServiceTemplate(slug: "ghost", slogan: "A publishing platform.", category: "cms"),
                ServiceTemplate(slug: "n8n", slogan: "Workflow automation.", category: "automation"),
                ServiceTemplate(slug: "uptime-kuma", slogan: "A monitoring tool.", category: "monitoring"),
            ])
        )
        .navigationTitle("New Resource")
    }
}

#Preview("Loading") {
    NavigationStack {
        CatalogGallery(shelves: [], isLoading: true)
    }
}
