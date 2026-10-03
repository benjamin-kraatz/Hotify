import SwiftUI
import UserNotifications

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
    @State private var placeColors: PlaceColors
    /// The notification center keeps only a weak reference to its delegate.
    @State private var notificationRouter = NotificationRouter()
    #if os(macOS)
    @State private var notificationSettings = NotificationSettings()
    @State private var notificationWatcher = NotificationWatcher()
    #else
    @State private var deploymentActivities = DeploymentActivities()
    #endif
    @SwiftUI.Environment(\.scenePhase) private var scenePhase

    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @SwiftUI.Environment(\.openWindow) private var openWindow
    #endif

    init() {
        #if DEBUG
        let fixtureStore = FixtureEnvironment.makeStore()
        let store = fixtureStore ?? InstanceStore()
        if fixtureStore != nil { _variableLock = State(initialValue: VariableLock(isRequired: false)) }
        // Fixture instances write nothing to iCloud, so their colors last until the app quits.
        _placeColors = State(
            initialValue: fixtureStore == nil ? PlaceColors() : PlaceColors(defaults: nil, cloud: nil))
        #else
        let store = InstanceStore()
        _placeColors = State(initialValue: PlaceColors())
        #endif
        let companion = MenuBarModel()
        companion.connect(store)
        _instanceStore = State(initialValue: store)
        _menuBar = State(initialValue: companion)
        let router = NotificationRouter()
        UNUserNotificationCenter.current().delegate = router
        _notificationRouter = State(initialValue: router)
        #if os(macOS)
        let settings = NotificationSettings()
        let watcher = NotificationWatcher()
        watcher.start(store: store, settings: settings)
        _notificationSettings = State(initialValue: settings)
        _notificationWatcher = State(initialValue: watcher)
        #else
        let activities = DeploymentActivities()
        activities.connect(store)
        _deploymentActivities = State(initialValue: activities)
        #endif
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
            #endif
            .commands {
                #if os(macOS)
                CommandGroup(replacing: .appInfo) {
                    Button("About Hotify") {
                        openWindow(id: "about")
                    }
                }
                #endif
                // iPad lists these in its menu bar too.
                InstanceCommands()
                ProjectCommands()
            }
            // Not on `.inactive`: the Face ID prompt itself makes the scene inactive on iOS.
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    variableLock.lock()
                    #if os(iOS)
                    // Keeps Live Activities current for the moments iOS grants, then asks to look again later.
                    deploymentActivities.followInBackground()
                    #endif
                    // Leaving is the last chance to refresh widgets without spending their daily budget.
                    WidgetRefresh.all()
                }
            }

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(variableLock)
                .environment(instanceStore)
                .environment(menuBar)
                .environment(notificationSettings)
        }

        MenuBarExtra(isInserted: Binding(get: { menuBar.enabled }, set: { menuBar.enabled = $0 })) {
            MenuBarView().environment(menuBar)
        } label: {
            MenuBarIcon(model: menuBar)
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
        let activities = deploymentActivities
        WindowGroup { mainContent }
            .backgroundTask(.appRefresh(DeploymentActivities.refreshTaskID)) {
                await activities.refreshAll()
                await activities.scheduleRefresh()
            }
        #endif
    }

    private var mainContent: some View {
        ContentView()
            .environment(instanceStore)
            .environment(variableLock)
            .environment(menuBar)
            .environment(placeColors)
            #if os(iOS)
        .environment(deploymentActivities)
        .tint(.ember)
            #endif
    }
}
