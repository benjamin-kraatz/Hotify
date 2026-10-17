#if os(iOS)
import SwiftTerm
import SwiftUI
import UIKit

/// A key the bar above the keyboard sends.
enum TerminalKey: Hashable {
    case escape
    case tab
    /// Sticky: the next key goes out with Control held.
    case control
    case text(String)
    case up
    case down
    case left
    case right
    case hideKeyboard
}

/// The row above the keyboard: the keys a shell needs that the keyboard lacks. Arrows repeat while held.
struct TerminalKeyBar: View {
    var isControlArmed: Bool
    var onKey: (TerminalKey) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                // Arrows before the symbols: an iPhone shows the first eight, and the rest scroll in.
                HStack(spacing: 5) {
                    key("esc", .escape)
                    key("tab", .tab)
                    key("ctrl", .control, armed: isControlArmed)
                    gap
                    RepeatingKey(systemImage: "arrow.left", label: "Left") { onKey(.left) }
                    RepeatingKey(systemImage: "arrow.down", label: "Down") { onKey(.down) }
                    RepeatingKey(systemImage: "arrow.up", label: "Up") { onKey(.up) }
                    RepeatingKey(systemImage: "arrow.right", label: "Right") { onKey(.right) }
                    gap
                    key("~", .text("~"))
                    key("|", .text("|"))
                    key("/", .text("/"))
                    key("-", .text("-"))
                }
                .padding(.horizontal, 8)
            }
            Button {
                onKey(.hideKeyboard)
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .frame(width: 40, height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Hide Keyboard")
            .padding(.trailing, 6)
        }
        .frame(height: 44)
        .sensoryFeedback(.selection, trigger: isControlArmed)
    }

    private var gap: some View {
        Color.clear.frame(width: 4)
    }

    private func key(_ title: String, _ key: TerminalKey, armed: Bool = false) -> some View {
        Button {
            onKey(key)
        } label: {
            Text(title)
                .font(.system(.subheadline, design: .monospaced).weight(.medium))
                .frame(minWidth: 34)
                .frame(height: 32)
                .padding(.horizontal, 4)
                .foregroundStyle(armed ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(
                    armed ? AnyShapeStyle(.ember) : AnyShapeStyle(.background.opacity(0.9)), in: .rect(cornerRadius: 7)
                )
                .shadow(color: .black.opacity(0.25), radius: 0, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(armed ? .isSelected : [])
        .animation(.snappy(duration: 0.15), value: armed)
    }
}

/// A key that fires on touch and keeps firing while held, like a hardware key.
private struct RepeatingKey: View {
    var systemImage: String
    var label: String
    var action: () -> Void

    @State private var repeating: Task<Void, Never>?
    @State private var isPressed = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.medium))
            .frame(width: 34, height: 32)
            .foregroundStyle(.primary)
            .background(.background.opacity(isPressed ? 0.6 : 0.9), in: .rect(cornerRadius: 7))
            .shadow(color: .black.opacity(0.25), radius: 0, y: 1)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .onLongPressGesture(minimumDuration: .infinity, maximumDistance: 40) {
            } onPressingChanged: { pressing in
                isPressed = pressing
                if pressing {
                    start()
                } else {
                    repeating?.cancel()
                    repeating = nil
                }
            }
    }

    private func start() {
        action()
        repeating?.cancel()
        repeating = Task {
            try? await Task.sleep(for: .milliseconds(450))
            while !Task.isCancelled {
                action()
                try? await Task.sleep(for: .milliseconds(70))
            }
        }
    }
}

/// Keeps the key bar's view of Ctrl in step with the terminal's, which lets go after one key.
@Observable
private final class KeyBarState {
    var isControlArmed = false
}

/// Hosts the key bar as the terminal's input accessory.
final class TerminalKeyBarHost: UIInputView {
    private weak var terminal: HotifyTerminalView?
    private let state = KeyBarState()
    private var hosting: UIHostingController<AnyView>?

    init(terminal: HotifyTerminalView) {
        self.terminal = terminal
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 44), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        let state = state
        let bar = KeyBarRoot(state: state) { [weak self] key in self?.press(key) }
        let hosting = UIHostingController(rootView: AnyView(bar))
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        self.hosting = hosting
        // SwiftTerm posts this when it sends the key Ctrl was armed for. The name is its own, not public.
        NotificationCenter.default.addObserver(
            self, selector: #selector(controlReset),
            name: Notification.Name("SwiftTerm.TerminalView.controlModifierReset"), object: terminal)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 44)
    }

    @objc private func controlReset() {
        state.isControlArmed = false
    }

    private func press(_ key: TerminalKey) {
        guard let terminal else { return }
        UIDevice.current.playInputClick()
        switch key {
        case .escape:
            terminal.send([0x1B])
        case .tab:
            terminal.send([0x09])
        case .control:
            terminal.controlModifier.toggle()
            state.isControlArmed = terminal.controlModifier
        case .text(let text):
            // Goes through the keyboard's path, so an armed Ctrl applies to it.
            terminal.insertText(text)
        case .up:
            terminal.send(cursor ? EscapeSequences.moveUpApp : EscapeSequences.moveUpNormal)
        case .down:
            terminal.send(cursor ? EscapeSequences.moveDownApp : EscapeSequences.moveDownNormal)
        case .left:
            terminal.send(cursor ? EscapeSequences.moveLeftApp : EscapeSequences.moveLeftNormal)
        case .right:
            terminal.send(cursor ? EscapeSequences.moveRightApp : EscapeSequences.moveRightNormal)
        case .hideKeyboard:
            _ = terminal.resignFirstResponder()
        }
    }

    /// Full-screen programs ask for application cursor keys, which use a different sequence.
    private var cursor: Bool {
        terminal?.getTerminal().applicationCursor ?? false
    }
}

/// Observes the shared state so the bar redraws when Ctrl lets go.
private struct KeyBarRoot: View {
    var state: KeyBarState
    var onKey: (TerminalKey) -> Void

    var body: some View {
        TerminalKeyBar(isControlArmed: state.isControlArmed, onKey: onKey)
    }
}

#Preview {
    VStack(spacing: 12) {
        TerminalKeyBar(isControlArmed: false, onKey: { _ in })
        TerminalKeyBar(isControlArmed: true, onKey: { _ in })
    }
    .background(Color(.systemGray4))
}
#endif
