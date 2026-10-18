import SwiftTerm
import SwiftUI

/// SwiftTerm's terminal view, fed from and typing into the model's session, drawn in the chosen palette and size.
///
/// The view lives as long as the screen does, across reconnects, so the scrollback of an earlier shell stays
/// above the divider the model prints.
struct TerminalCanvas {
    var model: TerminalModel
    var surface: TerminalSurface
    var palette: TerminalPalette
    var fontSize: Double
    var optionAsMeta: Bool
    var confirmsPaste: Bool
    /// A pinch on iOS asks for a new size through this. The Mac zooms from its menu.
    var onFontSizeChange: (Double) -> Void = { _ in }

    static let scrollback = 10_000

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, surface: surface)
    }

    final class Coordinator: NSObject, TerminalViewDelegate {
        let model: TerminalModel
        let surface: TerminalSurface
        /// What the view draws with now, so an update only touches what changed.
        private var palette: TerminalPalette?
        private var fontSize: Double?
        #if os(iOS)
        var onFontSizeChange: ((Double) -> Void)?
        private var pinchedFrom: Double = 0
        #endif

        init(model: TerminalModel, surface: TerminalSurface) {
            self.model = model
            self.surface = surface
        }

        func attach(_ view: HotifyTerminalView) {
            view.terminalDelegate = self
            view.onFind = { [weak surface] in
                guard let surface else { return }
                surface.findTerm = surface.findTerm ?? ""
            }
            view.onPasteCheck = { [weak surface] check in
                surface?.pendingPaste = check
            }
            surface.view = view
            model.attach { [weak view] bytes in
                view?.feed(byteArray: bytes[...])
            }
        }

        func apply(
            palette: TerminalPalette, fontSize: Double, optionAsMeta: Bool, confirmsPaste: Bool,
            to view: HotifyTerminalView
        ) {
            if self.fontSize != fontSize {
                self.fontSize = fontSize
                view.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
            }
            if self.palette != palette {
                self.palette = palette
                view.installColors(palette.ansi.map { SwiftTerm.Color(rgb: $0) })
                view.nativeForegroundColor = PlatformColor(rgb: palette.foreground)
                view.nativeBackgroundColor = PlatformColor(rgb: palette.background)
                view.caretColor = PlatformColor(rgb: palette.cursor)
                view.caretTextColor = PlatformColor(rgb: palette.cursorText)
                view.selectedTextBackgroundColor = PlatformColor(rgb: palette.selection)
                view.selectedTextForegroundColor = PlatformColor(rgb: palette.selectedText)
                #if os(iOS)
                // iOS paints the canvas through the layer, and the keyboard should match it.
                view.layer.backgroundColor = PlatformColor(rgb: palette.background).cgColor
                view.keyboardAppearance = palette.isDark ? .dark : .light
                #endif
            }
            view.confirmsPaste = confirmsPaste
            #if os(macOS)
            view.optionAsMetaKey = optionAsMeta
            #endif
        }

        // MARK: TerminalViewDelegate

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            model.resize(columns: newCols, rows: newRows)
        }

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            model.send(Array(data))
        }

        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            guard let url = URL(string: link), let scheme = url.scheme, ["http", "https"].contains(scheme) else {
                return
            }
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #else
            UIApplication.shared.open(url)
            #endif
        }

        func setTerminalTitle(source: TerminalView, title: String) {
            surface.title = title.isEmpty ? nil : title
        }

        /// OSC 7 carries a `file://host/path` URL.
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            let path = directory.flatMap { URL(string: $0)?.path(percentEncoded: false) } ?? directory
            surface.directory = path.flatMap { $0.isEmpty ? nil : $0 }
        }

        func bell(source: TerminalView) {
            surface.bells += 1
        }

        /// OSC 52: a program such as tmux or Vim puts text on the clipboard. Hotify lets it write, which is what a
        /// yank over SSH is for.
        func clipboardCopy(source: TerminalView, content: Data) {
            guard let text = String(data: content, encoding: .utf8) else { return }
            #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            #else
            UIPasteboard.general.string = text
            #endif
        }

        /// A program on the server doesn't get to read this device's clipboard.
        func clipboardRead(source: TerminalView) -> Data? {
            nil
        }

        func scrolled(source: TerminalView, position: Double) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

        #if os(iOS)
        @objc func pinched(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                pinchedFrom = fontSize ?? TerminalPreferences.defaultFontSize
            case .changed:
                onFontSizeChange?(TerminalPreferences.clamp(pinchedFrom * gesture.scale))
            default:
                break
            }
        }
        #endif
    }

    private func makeView(context: Context) -> HotifyTerminalView {
        let options = TerminalOptions(scrollback: Self.scrollback)
        let view = HotifyTerminalView(
            frame: .zero, font: .monospacedSystemFont(ofSize: fontSize, weight: .regular), options: options)
        // Bell: the chrome flashes, and the phone taps. Neither beeps.
        view.bellStyle = .sound
        context.coordinator.attach(view)
        context.coordinator.apply(
            palette: palette, fontSize: fontSize, optionAsMeta: optionAsMeta, confirmsPaste: confirmsPaste, to: view)
        return view
    }

    private func update(_ view: HotifyTerminalView, context: Context) {
        context.coordinator.apply(
            palette: palette, fontSize: fontSize, optionAsMeta: optionAsMeta, confirmsPaste: confirmsPaste, to: view)
    }
}

#if os(macOS)
typealias PlatformColor = NSColor

extension TerminalCanvas: NSViewRepresentable {
    func makeNSView(context: Context) -> HotifyTerminalView {
        let view = makeView(context: context)
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ view: HotifyTerminalView, context: Context) {
        update(view, context: context)
    }

    static func dismantleNSView(_ view: HotifyTerminalView, coordinator: Coordinator) {
        coordinator.model.detach()
        coordinator.surface.view = nil
    }
}
#else
typealias PlatformColor = UIColor

extension TerminalCanvas: UIViewRepresentable {
    func makeUIView(context: Context) -> HotifyTerminalView {
        let view = makeView(context: context)
        view.inputAccessoryView = TerminalKeyBarHost(terminal: view)
        context.coordinator.onFontSizeChange = onFontSizeChange
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinched))
        view.addGestureRecognizer(pinch)
        DispatchQueue.main.async { _ = view.becomeFirstResponder() }
        return view
    }

    func updateUIView(_ view: HotifyTerminalView, context: Context) {
        context.coordinator.onFontSizeChange = onFontSizeChange
        update(view, context: context)
    }

    static func dismantleUIView(_ view: HotifyTerminalView, coordinator: Coordinator) {
        coordinator.model.detach()
        coordinator.surface.view = nil
    }
}
#endif

extension PlatformColor {
    /// A color from `0xRRGGBB`.
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension SwiftTerm.Color {
    /// A palette entry from `0xRRGGBB`.
    convenience init(rgb: UInt32) {
        self.init(red8: UInt16((rgb >> 16) & 0xFF), green8: UInt16((rgb >> 8) & 0xFF), blue8: UInt16(rgb & 0xFF))
    }
}
