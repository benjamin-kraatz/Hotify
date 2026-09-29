import SwiftUI

/// The first screen, before any instance is saved. The flame lights, then the words and the button follow.
struct WelcomeView: View {
    var onAdd: () -> Void

    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var isShowingAbout = false

    var body: some View {
        VStack(spacing: 30) {
            FlameGlyph(heat: .lit, height: 128, ignitesOnAppear: true)

            VStack(spacing: 10) {
                Text("Hotify")
                    .font(.system(size: 54, weight: .black).width(.expanded))
                Text("Start, stop, and watch everything on your Coolify servers.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .opacity(step >= 1 ? 1 : 0)
            .offset(y: step >= 1 || reduceMotion ? 0 : 12)

            VStack(spacing: 14) {
                Button(action: onAdd) {
                    Label("Add an instance", systemImage: "plus")
                        .padding(.horizontal, 6)
                }
                .glassButton(prominent: true)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Text("You need its URL and an API token. Create one in Coolify under Keys & Tokens.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                #if os(iOS)
                Button("About Hotify") {
                    isShowingAbout = true
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                #endif
            }
            .opacity(step >= 2 ? 1 : 0)
            .offset(y: step >= 2 || reduceMotion ? 0 : 12)
        }
        .padding(40)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        #endif
        #if os(iOS)
        .sheet(isPresented: $isShowingAbout) {
            NavigationStack {
                AboutView(buildInfo: .current)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { isShowingAbout = false }
                    }
                }
            }
        }
        #endif
        .task {
            try? await Task.sleep(for: .milliseconds(420))
            withAnimation(.smooth(duration: 0.6)) { step = 1 }
            try? await Task.sleep(for: .milliseconds(160))
            withAnimation(.smooth(duration: 0.6)) { step = 2 }
        }
    }
}

#Preview {
    WelcomeView {}
        .frame(width: 800, height: 600)
}
