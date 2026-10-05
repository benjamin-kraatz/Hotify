import SwiftUI

/// The ways to create an application, one card per source.
struct ApplicationGallery: View {
    var onSelect: (ApplicationSource) -> Void = { _ in }

    @SwiftUI.Environment(\.horizontalSizeClass) private var sizeClass

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: sizeClass == .compact ? 150 : 210, maximum: 340), spacing: 14)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("New application")
                        .font(.display(.title2))
                    Text(
                        "Pick where the code comes from. Coolify places it on the server you choose,"
                            + " and can deploy it as soon as it exists."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(ApplicationSource.allCases) { source in
                        Button {
                            onSelect(source)
                        } label: {
                            TemplateCard(name: source.title, slogan: source.slogan, logoURL: nil)
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
    ApplicationGallery()
        .frame(width: 760, height: 640)
}
