import CoolifyAPI
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A template's logo on a light tile, the way it would sit on its own website. Many logos are dark, and a tile keeps
/// them legible in Dark Mode. Until the logo loads, or when the instance has none, the tile shows the initial.
struct TemplateLogo: View {
    var name: String
    var url: URL?
    var size: CGFloat = 44

    @State private var image: Image?

    private var radius: CGFloat { size * 0.26 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(image == nil ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(Color(white: 0.97)))
            if let image {
                image
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(size * 0.17)
                    .transition(.opacity)
            } else {
                Text(verbatim: String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.42, weight: .heavy).width(.expanded))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
        }
        .animation(.easeOut(duration: 0.25), value: image != nil)
        .task(id: url) {
            image = nil
            guard let url else { return }
            image = await LogoStore.shared.image(for: url)
        }
        .accessibilityHidden(true)
    }
}

/// Logos fetched this session. A logo the instance lacks is remembered as missing, so it is asked for once.
private final class LogoStore {
    static let shared = LogoStore()

    private var images: [URL: Image?] = [:]
    private var inFlight: [URL: Task<Image?, Never>] = [:]
    private let session = CoolifyClient.makeSession()

    func image(for url: URL) async -> Image? {
        if let cached = images[url] { return cached }
        if let task = inFlight[url] { return await task.value }
        let session = session
        let task = Task<Image?, Never> {
            guard let (data, response) = try? await session.data(from: url),
                (response as? HTTPURLResponse)?.statusCode == 200
            else { return nil }
            return Self.decode(data)
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        images[url] = .some(image)
        return image
    }

    /// Decodes PNG, JPEG, WebP, and SVG. ImageIO cannot read SVG, so `AsyncImage` would miss most logos.
    private static func decode(_ data: Data) -> Image? {
        #if os(macOS)
        NSImage(data: data).map(Image.init(nsImage:))
        #else
        UIImage(data: data).map(Image.init(uiImage:))
        #endif
    }
}

#Preview {
    HStack(spacing: 16) {
        TemplateLogo(name: "ghost", url: nil)
        TemplateLogo(name: "n8n", url: nil, size: 72)
    }
    .padding(40)
}
