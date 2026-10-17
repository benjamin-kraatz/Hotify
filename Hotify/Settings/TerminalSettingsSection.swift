import SwiftUI

/// The terminal's look and manners: theme, text size, Option on the Mac, and the paste check.
struct TerminalSettingsSection: View {
    @AppStorage(TerminalPreferences.themeKey) private var theme = TerminalTheme.ember
    @AppStorage(TerminalPreferences.fontSizeKey) private var fontSize = TerminalPreferences.defaultFontSize
    @AppStorage(TerminalPreferences.optionAsMetaKey) private var optionAsMeta = false
    @AppStorage(TerminalPreferences.confirmsPasteKey) private var confirmsPaste = true
    @SwiftUI.Environment(\.colorScheme) private var colorScheme

    private var palette: TerminalPalette { theme.palette(for: colorScheme) }

    var body: some View {
        Section {
            Picker(selection: $theme) {
                ForEach(TerminalTheme.allCases) { theme in
                    Text(theme.title).tag(theme)
                }
            } label: {
                Label {
                    Text("Theme")
                } icon: {
                    Image(systemName: "paintpalette")
                        .foregroundStyle(.ember)
                }
            }
            LabeledContent("Colors") {
                HStack(spacing: 3) {
                    ForEach(palette.ansi.prefix(8), id: \.self) { value in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(rgb: value))
                            .frame(width: 14, height: 14)
                    }
                }
                .padding(5)
                .background(Color(rgb: palette.background), in: .rect(cornerRadius: 6))
                .animation(.snappy, value: palette)
            }
            Stepper(
                value: $fontSize, in: TerminalPreferences.fontSizes, step: TerminalPreferences.fontStep
            ) {
                LabeledContent("Text size", value: "\(Int(fontSize)) pt")
            }
            #if os(macOS)
            Toggle(isOn: $optionAsMeta) {
                Text("Use Option as Meta")
                Text("Option sends Escape before the key, for Emacs and readline. Off keeps it for typing @ and |.")
            }
            #endif
            Toggle(isOn: $confirmsPaste) {
                Text("Ask before pasting several lines")
                Text("A shell runs each pasted line. Hotify shows what the clipboard holds before it goes in.")
            }
        } header: {
            Text("Terminal")
        } footer: {
            #if os(macOS)
            Text("⌘+ and ⌘- change the text size while you work. Find is ⌘F, and ⌘K clears the scrollback.")
            #else
            Text("Pinch the terminal to change the text size while you work.")
            #endif
        }
    }
}

#Preview {
    Form {
        TerminalSettingsSection()
    }
    .formStyle(.grouped)
    .frame(width: 500)
}
