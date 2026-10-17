import CoolifyAPI
import SwiftUI

/// The New Resource sheet's first column: the template shelves, a compose file or an image of one's own, the database
/// engines, and the repositories an application can come from. A compose file is one row here, not a card in the way.
struct SourceSidebar: View {
    @Binding var selection: ProvisioningSource
    var shelves: [TemplateShelf]

    @State private var showsEveryShelf = false

    /// Shelves shown before the user asks for the rest, so the other sections stay in view.
    private static let leadingShelves = 6

    private var visibleShelves: [TemplateShelf] {
        if showsEveryShelf { return shelves }
        let leading = Array(shelves.prefix(Self.leadingShelves))
        // A shelf chosen from the hidden ones stays in view.
        if case .list(.shelf(let category)) = selection, !leading.contains(where: { $0.category == category }),
            let chosen = shelves.first(where: { $0.category == category })
        {
            return leading + [chosen]
        }
        return leading
    }

    var body: some View {
        List(selection: Binding(get: { Optional(selection) }, set: { if let new = $0 { selection = new } })) {
            Section("Templates") {
                row(.list(.popular), count: CatalogScope.popular.count(in: shelves))
                row(.list(.all), count: CatalogScope.all.count(in: shelves))
                ForEach(visibleShelves) { shelf in
                    row(.list(.shelf(shelf.category)), count: shelf.templates.count)
                }
                if shelves.count > Self.leadingShelves {
                    Button {
                        showsEveryShelf.toggle()
                    } label: {
                        Label(
                            showsEveryShelf ? "Fewer Categories" : "More Categories",
                            systemImage: showsEveryShelf ? "chevron.up" : "chevron.down")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            Section("Your Own") {
                row(.compose)
                row(.application(.dockerfile))
                row(.application(.dockerImage))
            }
            Section("Databases") {
                row(.list(.databases), title: "All Engines", count: DatabaseEngine.allCases.count)
            }
            Section("From a Repository") {
                row(.application(.publicGit))
                row(.application(.githubApp))
                row(.application(.deployKey))
            }
        }
        .listStyle(.sidebar)
        .animation(.snappy, value: showsEveryShelf)
    }

    private func row(_ source: ProvisioningSource, title: String? = nil, count: Int? = nil) -> some View {
        Label(title ?? source.title, systemImage: source.systemImage)
            .badge(count ?? 0)
            .tag(source)
    }
}

#Preview {
    @Previewable @State var selection = ProvisioningSource.list(.popular)
    SourceSidebar(
        selection: $selection,
        shelves: TemplateShelf.group([
            ServiceTemplate(slug: "ghost", slogan: "A publishing platform.", category: "cms"),
            ServiceTemplate(slug: "n8n", slogan: "Workflow automation.", category: "automation"),
            ServiceTemplate(slug: "uptime-kuma", slogan: "A monitoring tool.", category: "monitoring"),
        ])
    )
    .frame(width: 220, height: 640)
    .tint(.ember)
}
