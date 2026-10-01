import SwiftUI

/// Where a screen in the detail column goes back to: the name of that place, and how to get there.
struct DetailBack {
    var title: String
    var action: () -> Void
}

/// The leading end of the detail column's toolbar: the way back, when there is one, and on the Mac the screen's title.
///
/// The detail column swaps its screens in place rather than pushing them, so whichever view owns the column's
/// toolbar says where back leads. List this first in that toolbar, ahead of the screen's actions. Escape goes
/// back too.
struct DetailNavigation: ToolbarContent {
    /// Names the screen, such as `Application` or `Previews`. The name of the thing itself heads the screen below.
    var title: String
    /// `nil` at the top of the column.
    var back: DetailBack?

    var body: some ToolbarContent {
        if let back {
            ToolbarItem(placement: Self.backPlacement) {
                Button(action: back.action) {
                    Label("Back to \(back.title)", systemImage: "chevron.left")
                }
                .help("Back to \(back.title)")
                .keyboardShortcut(.cancelAction)
            }
        }
        #if os(macOS)
        // The window takes its title from the list column, and that one is hidden because the list's header
        // already names the instance. So the detail column writes its own title, as plain text beside the button.
        ToolbarItem {
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 4)
        }
        .sharedBackgroundVisibility(.hidden)
        // Keeps the title apart from the actions after it, which share one glass panel.
        ToolbarSpacer(.fixed)
        #endif
    }

    /// The Mac puts navigation items at the window's leading edge, over the list. The detail column's own section
    /// starts with its first ordinary item, which is where its back button belongs.
    private static var backPlacement: ToolbarItemPlacement {
        #if os(macOS)
        .automatic
        #else
        .topBarLeading
        #endif
    }
}

extension View {
    /// Hides the system's back button on iPhone while the detail column has a back button of its own. The system's
    /// one would skip the step back inside the column and go straight to the list.
    func replacesSystemBack(_ replaces: Bool) -> some View {
        #if os(iOS)
        navigationBarBackButtonHidden(replaces)
        #else
        self
        #endif
    }
}

#Preview {
    NavigationStack {
        Text("marketing-site")
            .navigationTitle("Application")
            .toolbar {
                DetailNavigation(title: "Application", back: DetailBack(title: "Website") {})
            }
    }
    .frame(width: 420, height: 200)
}
