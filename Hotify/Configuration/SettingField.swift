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

#Preview {
    @Previewable @State var host = "localhost"
    @Previewable @State var port: Int? = 8080
    @Previewable @State var interval: Int?
    Form {
        SettingField(title: "Host", text: $host, prompt: "localhost")
        NumberField(title: "Port", value: $port, prompt: "Exposed port")
        NumberField(title: "Interval", value: $interval, prompt: "5", unit: "s")
    }
    .formStyle(.grouped)
    .frame(width: 420, height: 240)
}
