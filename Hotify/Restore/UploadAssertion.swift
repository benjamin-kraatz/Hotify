#if os(iOS)
import UIKit
#endif

/// Asks iOS for a little more time while an upload runs, so a short switch to another app does not stop it. The Mac
/// keeps running anyway.
@MainActor
final class UploadAssertion {
    #if os(iOS)
    private var task = UIBackgroundTaskIdentifier.invalid
    #endif

    func begin() {
        #if os(iOS)
        guard task == .invalid else { return }
        task = UIApplication.shared.beginBackgroundTask(withName: "Upload database backup") { [weak self] in
            // iOS calls this on the main thread when the time it granted runs out. The upload stops with the app.
            MainActor.assumeIsolated { self?.end() }
        }
        #endif
    }

    func end() {
        #if os(iOS)
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
        #endif
    }
}
