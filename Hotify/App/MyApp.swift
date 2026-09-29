import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

#if os(macOS)
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !UserDefaults.standard.bool(forKey: MenuBarModel.enabledKey)
    }
}
#endif

@main struct MyApp: App {
    @State private var instanceStore: InstanceStore
    @State private var menuBar: MenuBarModel
    @State private var variableLock = VariableLock()
    @SwiftUI.Environment(\.scenePhase) private var scenePhase

    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @SwiftUI.Environment(\.openWindow) private var openWindow
    #endif

    init() {
        let store = InstanceStore()
        let companion = MenuBarModel()
        companion.connect(store)
        _instanceStore = State(initialValue: store)
        _menuBar = State(initialValue: companion)
        #if os(iOS)
        // SwiftUI has no hook for navigation title fonts, so large titles pick up the brand's wide face here.
        let wide = UIFont.systemFont(ofSize: 34, weight: .heavy, width: .expanded)
        UINavigationBar.appearance().largeTitleTextAttributes = [
            .font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: wide)
        ]
        #endif
    }

    var body: some Scene {
        mainScene
            #if os(macOS)
        .defaultSize(width: 1240, height: 780)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Hotify") {
                    openWindow(id: "about")
                }
            }
        }
            #endif
            // Not on `.inactive`: the Face ID prompt itself makes the scene inactive on iOS.
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    variableLock.lock()
                }
            }

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(variableLock)
                .environment(instanceStore)
                .environment(menuBar)
        }

        MenuBarExtra(
            "Hotify", systemImage: "flame", isInserted: Binding(get: { menuBar.enabled }, set: { menuBar.enabled = $0 })
        ) {
            MenuBarView().environment(menuBar)
        }
        .menuBarExtraStyle(.window)

        Window("About Hotify", id: "about") {
            AboutView(buildInfo: .current)
                .frame(width: 400, height: 584)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .windowStyle(.hiddenTitleBar)
        .restorationBehavior(.disabled)
        #endif
    }

    @SceneBuilder
    private var mainScene: some Scene {
        #if os(macOS)
        Window("Hotify", id: "main") { mainContent }
        #else
        WindowGroup { mainContent }
        #endif
    }

    private var mainContent: some View {
        ContentView()
            .environment(instanceStore)
            .environment(variableLock)
            .environment(menuBar)
            #if os(iOS)
        .tint(.ember)
            #endif
    }
}
