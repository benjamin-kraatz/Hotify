import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
import UniformTypeIdentifiers
#endif

/// Copies a secret so it does not linger or travel further than the paste it was meant for.
enum SecretPasteboard {
    static func copy(_ text: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // The nspasteboard.org marker asks clipboard managers not to keep a history of this entry.
        pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        #else
        // Stay off Universal Clipboard, and clear after two minutes.
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: text]],
            options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(120)]
        )
        #endif
    }
}
