import SwiftUI

/// What a Shortcut automation can and can't do on this device, at the top of the dialog that makes one. Each line is
/// one fact, so the Mac and iPhone versions differ only where the platforms do.
struct AutomationLimits: View {
    /// Whether Hotify keeps running in the menu bar once its windows close. Only the Mac asks.
    var keepsRunning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
        .accessibilityElement(children: .combine)
    }

    struct Line {
        var text: String
        var systemImage: String
        var isWarning = false
    }

    static func lines(keepsRunning: Bool) -> [Line] {
        #if os(macOS)
        [
            Line(
                text:
                    "Hotify opens your Shortcut by name and hands it the event as JSON text. The Shortcut does what you built it to, with its own permissions.",
                systemImage: "square.2.layers.3d"),
            Line(
                text:
                    "It runs on this Mac only while Hotify runs and checks the instance, every 30 seconds. Quitting Hotify or putting the Mac to sleep pauses it, and what happened meanwhile isn't run later.",
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
                text: "Saved on this Mac alone, so no other device runs it. Tokens and logs never leave Hotify.",
                systemImage: "lock.laptopcomputer"),
        ]
        #else
        [
            Line(
                text:
                    "Hotify opens your Shortcut by name and hands it the resource as JSON text. The Shortcut does what you built it to, with its own permissions.",
                systemImage: "square.2.layers.3d"),
            Line(
                text:
                    "iPhone can't keep Hotify watching in the background or start a Shortcut on its own, so it runs when you tap Run, and Hotify switches to Shortcuts. A Mac can run one when a deploy ends.",
                systemImage: "hand.tap", isWarning: true),
            Line(
                text: "Saved on this iPhone alone, so no other device runs it. Tokens and logs never leave Hotify.",
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
    .frame(width: 480, height: 360)
}

#Preview("Menu bar off") {
    Form {
        Section {
            AutomationLimits(keepsRunning: false)
        }
    }
    .formStyle(.grouped)
    .frame(width: 480, height: 360)
}
