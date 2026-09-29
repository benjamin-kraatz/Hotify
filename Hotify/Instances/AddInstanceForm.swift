import SwiftUI

struct AddInstanceForm: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss
    var onAdd: (String, String, String) throws -> Void

    @State private var name = ""
    @State private var baseURL = ""
    @State private var token = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            TextField("Name", text: $name)
            TextField("URL", text: $baseURL)
            SecureField("API token", text: $token)
            if let errorMessage {
                Text(errorMessage)
            }
            HStack {
                Button("Cancel") { dismiss() }
                Button("Add") { submit() }
                    .disabled(name.isEmpty || baseURL.isEmpty || token.isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 360)
    }

    private func submit() {
        do {
            try onAdd(name, baseURL, token)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    AddInstanceForm { _, _, _ in }
}
