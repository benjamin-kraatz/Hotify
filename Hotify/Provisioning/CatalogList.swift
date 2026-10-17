import CoolifyAPI
import SwiftUI

/// The New Resource sheet's middle column for a list: templates, engines, or search results, one row each.
/// Choosing a row opens it in the inspector beside the list.
struct CatalogList: View {
    var title: String
    var count: Int
    var entries: [CatalogEntry]
    @Binding var selection: CatalogEntry?
    var instanceRoot: URL?
    /// Whether the list is Coolify's template catalog, which may still be loading or may have failed.
    var isTemplates = false
    var isLoading = false
    var loadError: String?
    var query = ""
    var onRetry: () -> Void = {}

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    header
                    ForEach(entries) { entry in
                        Button {
                            selection = entry
                        } label: {
                            CatalogRow(entry: entry, instanceRoot: instanceRoot, isSelected: selection == entry)
                        }
                        .buttonStyle(.plain)
                        .id(entry.id)
                    }
                    emptyState
                    if isTemplates, !entries.isEmpty {
                        footnote
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 16)
            }
            // Arrow keys in the search field move the selection. Keep the chosen row in view.
            .onChange(of: selection) { _, entry in
                guard let entry else { return }
                proxy.scrollTo(entry.id)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(count, format: .number)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var emptyState: some View {
        if entries.isEmpty {
            Group {
                if !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else if isTemplates, let loadError {
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
                } else if isTemplates, isLoading {
                    VStack(spacing: 14) {
                        FlameGlyph(heat: .warming, height: 44)
                        Text("Fetching Coolify's catalog")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 320)
        }
    }

    private var footnote: some View {
        Text(
            "Templates come from Coolify's public catalog at cdn.coollabs.io, the same one your instance uses. Hotify sends no token there."
        )
        .font(.caption)
        .foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 10)
        .padding(.top, 14)
    }
}

#Preview {
    @Previewable @State var selection: CatalogEntry? = .engine(.postgresql)
    CatalogList(
        title: "Databases", count: DatabaseEngine.allCases.count,
        entries: DatabaseEngine.allCases.map(CatalogEntry.engine), selection: $selection
    )
    .frame(width: 520, height: 600)
}

#Preview("Loading") {
    CatalogList(
        title: "Popular", count: 0, entries: [], selection: .constant(nil), isTemplates: true, isLoading: true
    )
    .frame(width: 520, height: 500)
}
