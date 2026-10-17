import Foundation
import SwiftTerm

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The screen's handle on the canvas: what the program in the shell has told it, and what the chrome can ask of it.
///
/// The canvas sets `view` once it exists.
@Observable
final class TerminalSurface {
    /// The title the program set, through OSC 0 or 2, such as `root@abc123: /app`.
    var title: String?
    /// The shell's working directory, when it reports it through OSC 7.
    var directory: String?
    /// Counts bells, so the chrome can flash once per ring.
    var bells = 0
    /// Text that waits for a yes before it goes to the shell, because it has more than one line or a control
    /// character.
    var pendingPaste: PasteCheck?
    /// Set by the search bar; `nil` closes it.
    var findTerm: String?
    /// Where the current match sits, once a search ran.
    var matches: (index: Int, total: Int)?

    weak var view: TerminalView?

    /// Jumps to the next match of `term`, or the previous one, and remembers where it landed.
    func find(_ term: String, forward: Bool = true) {
        guard let view else { return }
        guard !term.isEmpty else {
            view.clearSearch()
            matches = nil
            return
        }
        let found = forward ? view.findNext(term) : view.findPrevious(term)
        let summary = view.searchMatchSummary(term)
        matches = found ? summary : (index: 0, total: summary.total)
    }

    func closeFind() {
        findTerm = nil
        matches = nil
        view?.clearSearch()
        focus()
    }

    /// Forgets the lines above the screen, and asks the shell to draw the screen again.
    func clearScrollback() {
        guard let view else { return }
        view.getTerminal().clearScrollback()
        // Ctrl-L: the shell clears and redraws its prompt, and a full-screen program just redraws.
        view.send([0x0C])
    }

    /// Sends text to the shell as if typed, after the paste check if it is on.
    func paste(_ text: String, checked: Bool) {
        (view as? HotifyTerminalView)?.pasteText(text, checked: checked)
    }

    /// Types a command and presses Return.
    func run(_ command: String) {
        view?.send(txt: command + "\r")
        focus()
    }

    func focus() {
        #if os(macOS)
        view?.window?.makeFirstResponder(view)
        #else
        _ = view?.becomeFirstResponder()
        #endif
    }
}
