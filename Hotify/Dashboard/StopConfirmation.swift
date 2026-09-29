import SwiftUI

extension View {
    /// Asks before stopping a resource, because a stray click should not take a site down.
    func stopConfirmation(for resource: Binding<ResourceSummary?>, onConfirm: @escaping (ResourceSummary) -> Void)
        -> some View
    {
        confirmationDialog(
            resource.wrappedValue.map { "Stop \($0.name)?" } ?? "",
            isPresented: Binding(
                get: { resource.wrappedValue != nil },
                set: { isPresented in
                    if !isPresented {
                        resource.wrappedValue = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: resource.wrappedValue
        ) { summary in
            Button("Stop", role: .destructive) {
                onConfirm(summary)
            }
        } message: { summary in
            Text(
                "Coolify stops its containers. Volumes and data stay in place, and you can start \(summary.name) again."
            )
        }
    }
}
