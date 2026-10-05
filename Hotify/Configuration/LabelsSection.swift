import SwiftUI

/// An application's proxy labels, and whether Coolify escapes dollar signs in them.
struct LabelsSection: View {
    @Binding var labels: String
    @Binding var escapesDollarSigns: Bool

    var body: some View {
        Section {
            TextField(
                "Labels",
                text: $labels,
                prompt: Text("traefik.http.routers.app.rule=Host(`app.example.com`)"),
                axis: .vertical
            )
            .lineLimit(4...12)
            .font(.body.monospaced())
            .autocorrectionDisabled()
            Toggle("Escape dollar signs", isOn: $escapesDollarSigns)
        } header: {
            Text("Labels")
        } footer: {
            Text(
                "Coolify turns $ into $$ while this is on, "
                    + "so turn it off when the labels should expand environment variables."
            )
        }
    }
}

#Preview("Labels") {
    @Previewable @State var labels = """
        traefik.http.middlewares.hotify-compress.compress=true
        traefik.http.routers.hotify.middlewares=hotify-compress
        traefik.http.services.hotify.loadbalancer.server.port=3000
        """
    @Previewable @State var escapesDollarSigns = true
    Form {
        LabelsSection(labels: $labels, escapesDollarSigns: $escapesDollarSigns)
    }
    .formStyle(.grouped)
    .frame(width: 480, height: 360)
}
