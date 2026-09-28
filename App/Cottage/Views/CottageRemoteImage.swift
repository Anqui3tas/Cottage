import SwiftUI
import ImageIO

// URLCache persists small previews; full packs use the shared download store.
struct CottageRemoteImage: View {
    let url: URL?
    var symbol = "photo"
    var fit = false
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CottageTheme.moss.opacity(0.07)
                if let image {
                    Image(uiImage: image).resizable()
                        .aspectRatio(contentMode: fit ? .fit : .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    Image(systemName: symbol).font(.largeTitle)
                        .foregroundStyle(CottageTheme.moss.opacity(0.5))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .task(id: url) {
            image = nil
            guard let url else { return }
            image = await CottagePreviewLoader.shared.load(url)
        }
    }
}

private actor CottagePreviewLoader {
    static let shared = CottagePreviewLoader()

    func load(_ url: URL) async -> UIImage? {
        let data: Data?
        if url.isFileURL { data = try? Data(contentsOf: url) }
        else { data = try? await CottageHTTP.data(from: url, maximumBytes: 20_000_000) }
        guard !Task.isCancelled, let data,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1000,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: thumbnail)
    }
}
