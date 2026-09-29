import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Hotify's identity and copyable build details, shared by macOS and iOS.
struct AboutView: View {
    var buildInfo: AppBuildInfo

    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 18) {
                    StokableFlame(height: 88, headroom: 24)

                    VStack(spacing: 8) {
                        Text("Hotify")
                            .font(.display())
                        Text("A little warmth for your servers.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 14) {
                    HStack {
                        Text("Version")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(buildInfo.version)
                            .fontWeight(.medium)
                    }
                    Divider()
                    HStack {
                        Text("Build")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(buildInfo.build)
                            .monospacedDigit()
                    }
                    Divider()
                    HStack {
                        Text("Commit")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(buildInfo.shortCommit)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .accessibilityLabel("Commit \(buildInfo.commit ?? "unavailable")")
                    }
                }
                .padding(20)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 20))
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(.primary.opacity(0.06))
                }

                Button {
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(buildInfo.copyableDetails, forType: .string)
                    #else
                    UIPasteboard.general.string = buildInfo.copyableDetails
                    #endif
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        copied = true
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy build details", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .glassButton()
                .controlSize(.large)
                .task(id: copied) {
                    guard copied else { return }
                    do {
                        try await Task.sleep(for: .seconds(2))
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                            copied = false
                        }
                    } catch {}
                }

                Text("An independent app for Coolify.\nNot affiliated with the Coolify project.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .padding(32)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
        }
        .background {
            LinearGradient(
                colors: [.ember.opacity(0.07), .clear],
                startPoint: .topLeading,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
        .navigationTitle("About Hotify")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview("Release") {
    AboutView(
        buildInfo: AppBuildInfo(
            version: "0.2.5", build: "42",
            commit: "6bb32a8541fe95869881e3c7e542640ab4331267"
        )
    )
    .frame(width: 400, height: 584)
}

#Preview("Missing metadata") {
    AboutView(
        buildInfo: AppBuildInfo(
            version: "0.2.5", build: "1",
            commit: nil
        )
    )
    .frame(width: 400, height: 624)
}
