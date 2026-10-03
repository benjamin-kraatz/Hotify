import CoolifyAPI
import SwiftUI

/// The databases Coolify creates on its own, one card per engine.
struct DatabaseGallery: View {
    var instanceRoot: URL?
    var onSelect: (DatabaseEngine) -> Void = { _ in }

    @SwiftUI.Environment(\.horizontalSizeClass) private var sizeClass

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: sizeClass == .compact ? 150 : 210, maximum: 340), spacing: 14)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("New database")
                        .font(.display(.title2))
                    Text(
                        "Pick an engine. Coolify creates it with a password of its own and starts it. Other resources on the server reach it by its internal address."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(DatabaseEngine.allCases) { engine in
                        Button {
                            onSelect(engine)
                        } label: {
                            TemplateCard(
                                name: engine.displayName, slogan: engine.slogan,
                                logoURL: engine.logoURL(instanceRoot: instanceRoot))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }
}

#Preview {
    DatabaseGallery()
        .frame(width: 760, height: 600)
}
