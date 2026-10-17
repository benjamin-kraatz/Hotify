import SwiftUI

extension FocusedValues {
    /// Opens a terminal in the resource on screen.
    @Entry var openTerminal: OpenTerminalAction?
    /// What the terminal on screen can do from the menu bar.
    @Entry var terminalActions: TerminalActions?
}

/// Opens a terminal in one resource. Only one resource is on screen at a time, so every one is equal.
struct OpenTerminalAction: Equatable {
    var open: () -> Void

    func callAsFunction() { open() }

    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

/// The terminal's menu actions. One terminal is on screen at a time, so every one is equal.
struct TerminalActions: Equatable {
    var zoom: (TerminalZoom) -> Void
    var clear: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

/// The Terminal menu: open one, size its text, and clear it. Find lives in Edit, where the Mac keeps it.
struct TerminalCommands: Commands {
    @FocusedValue(\.openTerminal) private var openTerminal
    @FocusedValue(\.terminalActions) private var actions

    var body: some Commands {
        CommandMenu("Terminal") {
            // The resource's toolbar button has no shortcut of its own. The menu holds it, so it fires once.
            Button("Open Terminal") {
                openTerminal?()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(openTerminal == nil)
            Divider()
            Button("Bigger Text") {
                actions?.zoom(.bigger)
            }
            .keyboardShortcut("+")
            .disabled(actions == nil)
            Button("Smaller Text") {
                actions?.zoom(.smaller)
            }
            .keyboardShortcut("-")
            .disabled(actions == nil)
            Button("Actual Size") {
                actions?.zoom(.reset)
            }
            .keyboardShortcut("0")
            .disabled(actions == nil)
            Divider()
            Button("Clear Scrollback") {
                actions?.clear()
            }
            .keyboardShortcut("k")
            .disabled(actions == nil)
        }
    }
}
