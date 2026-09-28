import CryptoKit
import Foundation
import ImageIO

nonisolated struct CottageInstalledPack: Codable, Hashable, Identifiable, Sendable {
    let entry: CottageArtworkEntry
    var id: String { entry.id }

    func fileURL(for file: CottageMediaFile, in directory: URL? = CottageSharedContainer.installedPacksDirectory) -> URL? {
        directory?
            .appending(path: CottageDownloads.directoryName(for: id))
            .appending(path: file.sha256 + ".png")
    }
}

// The app and Messages read the same completed packs. Partial downloads stay hidden.
actor CottageDownloads {
    static let shared = CottageDownloads()
    private let directory: URL?
    private let session: URLSession

    init(directory: URL? = CottageSharedContainer.installedPacksDirectory, session: URLSession = .shared) {
        self.directory = directory
        self.session = session
    }

    nonisolated static func directoryName(for id: String) -> String {
        SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func installedPacks() throws -> [CottageInstalledPack] {
        try recordedPacks().filter { pack in
            (pack.entry.artwork.files ?? []).allSatisfy { file in
                guard let url = pack.fileURL(for: file, in: directory) else { return false }
                return FileManager.default.fileExists(atPath: url.path)
            }
        }
    }

    private func recordedPacks() throws -> [CottageInstalledPack] {
        guard let root = directory else { return [] }
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            .compactMap { directory in
                guard let data = try? Data(contentsOf: directory.appending(path: "pack.json")),
                      let pack = try? JSONDecoder().decode(CottageInstalledPack.self, from: data),
                      directory.lastPathComponent == Self.directoryName(for: pack.id) else { return nil }
                return pack
            }
            .sorted { $0.entry.artwork.title.localizedStandardCompare($1.entry.artwork.title) == .orderedAscending }
    }

    func install(_ entry: CottageArtworkEntry) async throws -> CottageInstalledPack {
        guard let root = directory else {
            throw CottageDownloadError.sharedStorageUnavailable
        }
        let files = entry.artwork.files ?? []
        guard !files.isEmpty else { throw CottageDownloadError.invalidImage }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appending(path: Self.directoryName(for: entry.id))
        let staging = root.appending(path: ".download-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        for file in files {
            try Task.checkCancellation()
            let oldFile = destination.appending(path: file.sha256 + ".png")
            let data: Data
            if let existing = try? Data(contentsOf: oldFile), Self.digest(existing) == file.sha256 {
                data = existing
            } else {
                data = try await CottageHTTP.data(from: file.url, maximumBytes: 20_000_000, session: session)
            }
            guard Self.digest(data) == file.sha256 else { throw CottageDownloadError.checksumMismatch }
            try Self.validateImage(data)
            try data.write(to: staging.appending(path: file.sha256 + ".png"), options: .atomic)
        }
        let pack = CottageInstalledPack(entry: entry)
        try JSONEncoder().encode(pack).write(to: staging.appending(path: "pack.json"), options: .atomic)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
        } else {
            try FileManager.default.moveItem(at: staging, to: destination)
        }
        return pack
    }

    // Preserve artists' originals; create a size-limited copy only for Messages.
    func stickerURL(for file: CottageMediaFile, in pack: CottageInstalledPack) throws -> URL {
        guard let original = pack.fileURL(for: file, in: directory) else {
            throw CottageDownloadError.sharedStorageUnavailable
        }
        let prepared = original.deletingLastPathComponent().appending(path: file.sha256 + "-messages.png")
        if FileManager.default.fileExists(atPath: prepared.path) { return prepared }
        let data = try Data(contentsOf: original)
        guard Self.digest(data) == file.sha256 else { throw CottageDownloadError.checksumMismatch }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw CottageDownloadError.invalidImage
        }
        for size in [618, 408, 300, 206, 128] {
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: size,
                kCGImageSourceCreateThumbnailWithTransform: true
            ] as CFDictionary) else { throw CottageDownloadError.invalidImage }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else {
                throw CottageDownloadError.invalidImage
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw CottageDownloadError.invalidImage }
            if output.length <= 500_000 {
                try (output as Data).write(to: prepared, options: .atomic)
                return prepared
            }
        }
        throw CottageDownloadError.invalidSticker
    }

    func remove(_ id: String) throws {
        guard let root = directory else { return }
        let directory = root.appending(path: Self.directoryName(for: id))
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    // Only called after a complete, validated catalog was fetched successfully.
    func reconcile(with index: CottageCatalogIndex) throws -> [CottageInstalledPack] {
        let current = Dictionary(uniqueKeysWithValues: index.artworks.map { ($0.id, $0) })
        for pack in try recordedPacks() {
            guard let entry = current[pack.id], entry.artwork.deliveryKind == .cottage,
                  entry.creditedArtists.map(\.usage) == pack.entry.creditedArtists.map(\.usage) else {
                try remove(pack.id)
                continue
            }
            // Remove withdrawn/changed images, retaining unchanged files for the next download.
            let hashes = Set((entry.artwork.files ?? []).map(\.sha256))
            for file in pack.entry.artwork.files ?? [] where !hashes.contains(file.sha256) {
                if let url = pack.fileURL(for: file, in: directory), FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                    let prepared = url.deletingLastPathComponent().appending(path: file.sha256 + "-messages.png")
                    if FileManager.default.fileExists(atPath: prepared.path) {
                        try FileManager.default.removeItem(at: prepared)
                    }
                }
            }
            // Keep attribution and profile changes current without downloading images again.
            let updated = CottageInstalledPack(entry: entry)
            if let root = directory {
                try JSONEncoder().encode(updated).write(
                    to: root.appending(path: Self.directoryName(for: entry.id)).appending(path: "pack.json"),
                    options: .atomic
                )
            }
        }
        return try installedPacks()
    }

    nonisolated private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func validateImage(_ data: Data) throws {
        guard data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 8192, height <= 8192,
              width * height <= 40_000_000,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
            throw CottageDownloadError.invalidImage
        }
    }
}

nonisolated enum CottageDownloadError: LocalizedError {
    case sharedStorageUnavailable, invalidImage, invalidSticker, checksumMismatch

    var errorDescription: String? {
        switch self {
        case .sharedStorageUnavailable: String(localized: "Your saved packs couldn’t be opened. Please try again.")
        case .invalidImage: String(localized: "This image could not be opened.")
        case .invalidSticker: String(localized: "This artwork could not be prepared for Messages.")
        case .checksumMismatch: String(localized: "This artwork was updated. Pull down to refresh, then try again.")
        }
    }
}

nonisolated enum CottageHTTP {
    // Enforce the limit while streaming, before a large response can fill memory.
    static func data(from url: URL, maximumBytes: Int, revalidate: Bool = false, session: URLSession = .shared) async throws -> Data {
        guard url.scheme == "https" else { throw URLError(.badURL) }
        let request = URLRequest(url: url, cachePolicy: revalidate ? .reloadRevalidatingCacheData : .useProtocolCachePolicy, timeoutInterval: 30)
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse,
              response.url?.scheme == "https", (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard response.expectedContentLength <= maximumBytes else { throw URLError(.dataLengthExceedsMaximum) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < maximumBytes else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }
}
