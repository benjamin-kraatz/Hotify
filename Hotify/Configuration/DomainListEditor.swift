import SwiftUI

/// Edits a list of web addresses as form rows, one per address, each with a way to remove it. The section's
/// `DomainSectionHeader` adds a row, and the new row takes the focus.
struct DomainListEditor: View {
    @Binding var domains: [String]
    /// Says what the addresses are for, for VoiceOver.
    var owner: String

    @FocusState private var focused: Int?

    var body: some View {
        if domains.isEmpty {
            Text("No domain")
                .foregroundStyle(.secondary)
        }
        ForEach(domains.indices, id: \.self) { index in
            row(index)
                .focused($focused, equals: index)
        }
        .onChange(of: domains.count) { old, new in
            if new > old {
                focused = new - 1
            }
        }
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

/// A domains section's header: its title, and the button that adds a domain at the trailing end.
struct DomainSectionHeader: View {
    var title: String
    @Binding var domains: [String]
    var owner: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 8)
            Button("Add Domain", systemImage: "plus") {
                domains.append("https://")
            }
            .buttonStyle(.borderless)
            .textCase(nil)
            .help("Add a domain for \(owner)")
            .accessibilityHint("Adds an address for \(owner)")
        }
    }
}

#Preview {
    @Previewable @State var domains = ["https://hotify.example.com", "www.hotify.example.com"]
    @Previewable @State var none: [String] = []
    Form {
        Section {
            DomainListEditor(domains: $domains, owner: "marketing-site")
        } header: {
            DomainSectionHeader(title: "Domains", domains: $domains, owner: "marketing-site")
        }
        Section {
            DomainListEditor(domains: $none, owner: "worker")
        } header: {
            DomainSectionHeader(title: "worker", domains: $none, owner: "worker")
        }
    }
    .formStyle(.grouped)
    .frame(width: 480, height: 360)
}
