import SwiftUI

/// One end of a sync: the instance, the resource, and for an application which set of variables.
struct SyncEndpointCard: View {
    var title: String
    @Binding var endpoint: ResourceEndpoint?
    @Binding var isPreview: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            ResourcePicker(endpoint: $endpoint)
            // Only applications keep a second set of variables for pull request previews.
            if endpoint?.resource.kind == .application {
                Picker("Variables", selection: $isPreview) {
                    Text("Production").tag(false)
                    Text("Preview").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .transition(.opacity)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .well()
        .animation(.snappy, value: endpoint?.resource.kind)
    }
}

#Preview {
    @Previewable @State var endpoint: ResourceEndpoint?
    @Previewable @State var isPreview = false
    SyncEndpointCard(title: "Copy from", endpoint: $endpoint, isPreview: $isPreview)
        .fixedSize(horizontal: false, vertical: true)
        .padding()
        .frame(width: 360)
        .environment(InstanceStore(instances: []))
}
