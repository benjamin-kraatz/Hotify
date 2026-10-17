import SwiftTerm
import SwiftUI

/// SwiftTerm's terminal view, fed from and typing into the model's session.
struct TerminalCanvas {
    var model: TerminalModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    final class Coordinator: NSObject, TerminalViewDelegate {
        let model: TerminalModel

        init(model: TerminalModel) {
            self.model = model
        }

        func attach(_ view: TerminalView) {
            view.terminalDelegate = self
            model.attach { [weak view] bytes in
                view?.feed(byteArray: bytes[...])
            }
        }

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

        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }

    private static let fontSize: CGFloat = 12
}

#if os(macOS)
extension TerminalCanvas: NSViewRepresentable {
    func makeNSView(context: Context) -> TerminalView {
        let view = TerminalView(frame: .zero, font: .monospacedSystemFont(ofSize: Self.fontSize, weight: .regular))
        // Option types characters such as @ and | on many keyboards, so it stays a modifier and not Meta.
        view.optionAsMetaKey = false
        context.coordinator.attach(view)
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ view: TerminalView, context: Context) {}

    static func dismantleNSView(_ view: TerminalView, coordinator: Coordinator) {
        coordinator.model.detach()
    }
}
#else
extension TerminalCanvas: UIViewRepresentable {
    func makeUIView(context: Context) -> TerminalView {
        let view = TerminalView(frame: .zero, font: .monospacedSystemFont(ofSize: Self.fontSize, weight: .regular))
        context.coordinator.attach(view)
        DispatchQueue.main.async { _ = view.becomeFirstResponder() }
        return view
    }

    func updateUIView(_ view: TerminalView, context: Context) {}

    static func dismantleUIView(_ view: TerminalView, coordinator: Coordinator) {
        coordinator.model.detach()
    }
}
#endif
