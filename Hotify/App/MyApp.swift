import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

#if os(macOS)
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
#endif

@main struct MyApp: App {
    @State private var instanceStore = InstanceStore()

    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    init() {
        #if os(iOS)
        // SwiftUI has no hook for navigation title fonts, so large titles pick up the brand's wide face here.
        let wide = UIFont.systemFont(ofSize: 34, weight: .heavy, width: .expanded)
        UINavigationBar.appearance().largeTitleTextAttributes = [
            .font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: wide)
        ]
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(instanceStore)
                #if os(iOS)
            // iOS ignores the asset catalog accent here, though macOS honors it. `glassButton` undoes this
            // tint on plain glass buttons, which would otherwise fill solid red.
            .tint(.ember)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1240, height: 780)
        .windowToolbarStyle(.unified)
        #endif
    }
}
