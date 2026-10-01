import SwiftUI

/// Edits a list of web addresses as form rows, one per address, with a way to add another and to remove each.
struct DomainListEditor: View {
    @Binding var domains: [String]
    /// Says what the addresses are for, for VoiceOver and the field's prompt.
    var owner: String

    var body: some View {
        ForEach(domains.indices, id: \.self) { index in
            row(index)
        }
        Button("Add Domain", systemImage: "plus") {
            domains.append("https://")
        }
        .buttonStyle(.borderless)
        .accessibilityHint("Adds an address for \(owner)")
    }

    private func row(_ index: Int) -> some View {
        let address = Binding(
            get: { domains.indices.contains(index) ? domains[index] : "" },
            set: { if domains.indices.contains(index) { domains[index] = $0 } }
        )
        let trimmed = address.wrappedValue.trimmingCharacters(in: .whitespaces)
        let isValid = trimmed.isEmpty || ResourceConfiguration.isWebAddress(trimmed)
        return HStack(spacing: 8) {
            TextField("Domain", text: address, prompt: Text(verbatim: "https://app.example.com"))
                .labelsHidden()
                .autocorrectionDisabled()
                #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
                #endif
                .accessibilityLabel("Domain \(index + 1) of \(owner)")
            if !isValid {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.glow)
                    .help("Needs http:// or https:// and a host")
                    .accessibilityLabel("Not a web address")
                    .transition(.opacity)
            }
            Button("Remove", systemImage: "minus.circle.fill") {
                if domains.indices.contains(index) {
                    domains.remove(at: index)
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Remove this domain")
            .accessibilityLabel("Remove \(trimmed.isEmpty ? "this domain" : trimmed)")
        }
        .animation(.snappy, value: isValid)
    }
}

#Preview {
    @Previewable @State var domains = ["https://hotify.example.com", "www.hotify.example.com"]
    Form {
        Section("Domains") {
            DomainListEditor(domains: $domains, owner: "marketing-site")
        }
    }
    .formStyle(.grouped)
    .frame(width: 480, height: 260)
}
