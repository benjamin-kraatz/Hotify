import SwiftUI

/// The sheet frame shared by move, clone, and migrate: a title, Cancel, and the action that confirms.
struct PlacementChrome<Content: View>: View {
    var title: String
    var actionTitle: String
    var canAct: Bool
    var isBusy: Bool
    var failure: String?
    var onAct: () -> Void
    @ViewBuilder var content: () -> Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let failure {
                    Section {
                        Label(failure, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.glow)
                    }
                }
                content()
            }
            .formStyle(.grouped)
            .disabled(isBusy)
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(actionTitle, action: onAct)
                        .disabled(!canAct)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 480, minHeight: 400)
        #endif
        .interactiveDismissDisabled(isBusy)
    }
}

#Preview {
    PlacementChrome(title: "Move", actionTitle: "Move", canAct: true, isBusy: false, failure: nil, onAct: {}) {
        Section {
            Text("production")
        } footer: {
            Text("Running containers stay up.")
        }
    }
}
