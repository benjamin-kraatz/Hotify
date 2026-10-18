import SwiftUI

#if os(iOS)
import UIKit
#endif

/// What a Shortcut automation can and can't do on this device, as the card at the top of the dialog that makes one:
/// where it runs, then one fact per line, so the Mac and iPhone versions differ only where the platforms do.
struct AutomationLimits: View {
    /// Whether Hotify keeps running in the menu bar once its windows close. Only the Mac asks.
    var keepsRunning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: Self.deviceImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.ember)
                    .frame(width: 32, height: 32)
                    .background(.ember.opacity(0.12), in: .rect(cornerRadius: 9, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Runs on this \(Self.deviceName)")
                        .font(.headline)
                    Text("Not on the Coolify server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Self.lines(keepsRunning: keepsRunning), id: \.text) { line in
                    Label {
                        Text(line.text)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: line.systemImage)
                            .foregroundStyle(line.isWarning ? Color.glow : Color.ember)
                            .frame(width: 20)
                    }
                    .font(.callout)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    struct Line {
        var text: String
        var systemImage: String
        var isWarning = false
    }

    /// "Mac", "iPhone", or "iPad", for copy about this device.
    static var deviceName: String {
        #if os(macOS)
        "Mac"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }

    /// The device's own glyph, the counterpart of the server rack on the commands Coolify runs on its server.
    static var deviceImage: String {
        #if os(macOS)
        "laptopcomputer"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        #endif
    }

    static func lines(keepsRunning: Bool) -> [Line] {
        #if os(macOS)
        [
            Line(
                text:
                    "Hotify opens the Shortcut by name and hands it the event as JSON text. The Shortcut does the rest, with its own permissions.",
                systemImage: "square.2.layers.3d"),
            Line(
                text:
                    "Only while Hotify runs and checks the instance, every 30 seconds. Quitting Hotify or sleeping the Mac pauses that, and missed events don't run later.",
                systemImage: "clock"),
            keepsRunning
                ? Line(
                    text: "Hotify stays in the menu bar, so closing its window doesn't stop this.",
                    systemImage: "menubar.rectangle")
                : Line(
                    text: "Closing Hotify's last window quits it. Show it in the menu bar to keep watching.",
                    systemImage: "menubar.rectangle", isWarning: true),
            Line(
                text: "Shortcuts may come forward, or ask your permission, when it runs.",
                systemImage: "hand.raised"),
            Line(
                text: "Saved on this Mac only, so no other device runs it. The Shortcut never gets a token or a log.",
                systemImage: "lock.laptopcomputer"),
        ]
        #else
        [
            Line(
                text:
                    "Hotify opens the Shortcut by name and hands it the resource as JSON text. The Shortcut does the rest, with its own permissions.",
                systemImage: "square.2.layers.3d"),
            Line(
                text:
                    "\(deviceName) can't keep Hotify watching in the background or start a Shortcut by itself, so this runs when you tap Run, and Hotify switches to Shortcuts. The Mac app can run one when something happens.",
                systemImage: "hand.tap", isWarning: true),
            Line(
                text:
                    "Saved on this \(deviceName) only, so no other device runs it. The Shortcut never gets a token or a log.",
                systemImage: "lock.iphone"),
        ]
        #endif
    }
}

#Preview("Menu bar on") {
    Form {
        Section {
            AutomationLimits(keepsRunning: true)
        }
    }
    .formStyle(.grouped)
    .frame(width: 480, height: 400)
}

#Preview("Menu bar off") {
    Form {
        Section {
            AutomationLimits(keepsRunning: false)
        }
    }
    .formStyle(.grouped)
    .frame(width: 480, height: 400)
}
