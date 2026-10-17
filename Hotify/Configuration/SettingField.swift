import SwiftUI

/// A form row with its label on the leading side and a text field on the trailing one, the same on the Mac and on
/// iOS, where a bare text field in a form shows only its prompt.
struct SettingField: View {
    var title: String
    @Binding var text: String
    var prompt: String = ""

    var body: some View {
        LabeledContent(title) {
            TextField(title, text: $text, prompt: Text(verbatim: prompt))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                #if os(iOS)
            .textInputAutocapitalization(.never)
                #endif
        }
    }
}

/// A form row for a whole number that may be empty, such as a port or a number of seconds, with its unit after it.
struct NumberField: View {
    var title: String
    @Binding var value: Int?
    var prompt: String = ""
    var unit: String?

    private var text: Binding<String> {
        Binding(
            get: { value.map(String.init) ?? "" },
            set: { value = Int($0.filter(\.isASCII).filter(\.isNumber)) }
        )
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, text: text, prompt: Text(verbatim: prompt))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    #if os(iOS)
                .keyboardType(.numberPad)
                    #endif
                    .frame(maxWidth: 110)
                if let unit {
                    Text(unit)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A form row for a shell command or a list of patterns, in a monospaced field that grows to `lines` when given and
/// keeps to one line otherwise. The Mac puts the label beside the field, like every other row. iOS puts it above,
/// since a command needs the row's whole width.
struct CommandField: View {
    var title: String
    @Binding var text: String
    var prompt: String = ""
    var lines: ClosedRange<Int>?

    var body: some View {
        #if os(macOS)
        LabeledContent(title) {
            field
        }
        #else
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            field
        }
        #endif
    }

    private var field: some View {
        grown
            .labelsHidden()
            .font(.body.monospaced())
            .autocorrectionDisabled()
            #if os(iOS)
        // A command or path is ASCII, and takes no capital the keyboard adds on its own.
        .textInputAutocapitalization(.never)
        .keyboardType(.asciiCapable)
            #endif
    }

    /// The text with typographic punctuation put back. Smart Punctuation, which SwiftUI can't turn off for a field,
    /// types `’` for `'` and `—` for `--`, and a shell reads neither.
    private var plain: Binding<String> {
        Binding(
            get: { text },
            set: { text = Self.plain($0) }
        )
    }

    static func plain(_ text: String) -> String {
        var text = text
        for (typed, meant) in [("‘", "'"), ("’", "'"), ("“", "\""), ("”", "\""), ("—", "--"), ("–", "-")] {
            text = text.replacingOccurrences(of: typed, with: meant)
        }
        return text
    }

    @ViewBuilder
    private var grown: some View {
        if let lines {
            TextField(title, text: plain, prompt: Text(verbatim: prompt), axis: .vertical)
                .lineLimit(lines)
        } else {
            TextField(title, text: plain, prompt: Text(verbatim: prompt))
        }
    }
}

#Preview {
    @Previewable @State var host = "localhost"
    @Previewable @State var port: Int? = 8080
    @Previewable @State var interval: Int?
    @Previewable @State var command = "pnpm install --frozen-lockfile"
    @Previewable @State var patterns = "src/**\n!docs/**"
    Form {
        SettingField(title: "Host", text: $host, prompt: "localhost")
        NumberField(title: "Port", value: $port, prompt: "Exposed port")
        NumberField(title: "Interval", value: $interval, prompt: "5", unit: "s")
        CommandField(title: "Install", text: $command, prompt: "npm ci")
        CommandField(title: "Patterns", text: $patterns, prompt: "src/**", lines: 2...6)
    }
    .formStyle(.grouped)
    .frame(width: 420, height: 400)
}
