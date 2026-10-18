import SwiftTerm
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// SwiftTerm's view with Hotify's manners: a paste with more than one line asks first, Find opens the screen's own
/// bar, and on the Mac a right click gets a menu.
final class HotifyTerminalView: TerminalView {
    /// Asked before a paste that needs a look. Returns once the screen has the question on show.
    var onPasteCheck: ((PasteCheck) -> Void)?
    /// Opens the screen's search bar.
    var onFind: (() -> Void)?
    /// Whether a multi-line paste asks first. Off sends everything straight through.
    var confirmsPaste = true

    /// Sends text as if typed, wrapped for a program that asked for bracketed paste. With `checked`, a paste that
    /// needs a look goes to `onPasteCheck` instead.
    func pasteText(_ text: String, checked: Bool) {
        let check = PasteCheck(text: text)
        if checked, confirmsPaste, check.needsConfirmation, let onPasteCheck {
            onPasteCheck(check)
            return
        }
        if getTerminal().bracketedPasteMode {
            send(data: EscapeSequences.bracketedPasteStart[0...])
        }
        send(txt: check.normalized)
        if getTerminal().bracketedPasteMode {
            send(data: EscapeSequences.bracketedPasteEnd[0...])
        }
    }

    #if os(macOS)
    override func paste(_ sender: Any) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        pasteText(text, checked: true)
    }

    /// Edit > Find lands here while the terminal has the keyboard. The screen's bar takes it, and the rest of the
    /// find actions keep SwiftTerm's handling.
    override func performTextFinderAction(_ sender: Any?) {
        if let item = sender as? NSMenuItem, NSTextFinder.Action(rawValue: item.tag) == .showFindInterface {
            onFind?()
            return
        }
        super.performTextFinderAction(sender)
    }

    override func performFindPanelAction(_ sender: Any?) {
        if let item = sender as? NSMenuItem, item.tag == Int(NSFindPanelAction.showFindPanel.rawValue) {
            onFind?()
            return
        }
        super.performFindPanelAction(sender)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let copy = NSMenuItem(title: "Copy", action: #selector(copy(_:)), keyEquivalent: "")
        copy.isEnabled = selectionActive
        menu.addItem(copy)
        menu.addItem(NSMenuItem(title: "Paste", action: #selector(paste(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Select All", action: #selector(selectAll(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Find…", action: #selector(findFromMenu), keyEquivalent: ""))
        menu.autoenablesItems = false
        return menu
    }

    @objc private func findFromMenu() {
        onFind?()
    }
    #else
    override func paste(_ sender: Any?) {
        guard let text = UIPasteboard.general.string else { return }
        pasteText(text, checked: true)
    }

    /// ⌘F on a hardware keyboard, beside the shortcuts SwiftTerm already answers.
    override var keyCommands: [UIKeyCommand]? {
        let find = UIKeyCommand(title: "Find", action: #selector(findFromKeyboard), input: "f", modifierFlags: .command)
        find.wantsPriorityOverSystemBehavior = true
        return (super.keyCommands ?? []) + [find]
    }

    @objc private func findFromKeyboard() {
        onFind?()
    }
    #endif
}
