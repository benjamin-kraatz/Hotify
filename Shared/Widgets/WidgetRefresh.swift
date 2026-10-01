import WidgetKit

/// Asks every widget and control to read again, after something changed that they show.
enum WidgetRefresh {
    static func all() {
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
    }
}
