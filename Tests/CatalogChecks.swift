import CryptoKit
import Foundation
import ImageIO

// A deterministic transport: these checks never contact a repository.
final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    static var responses: [String: Data] = [:]
    static var requests: [String] = []
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let key = request.url!.absoluteString
        Self.lock.lock()
        Self.requests.append(key)
        let data = Self.responses[key]
        Self.lock.unlock()
        if let data {
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Length": String(data.count)])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        }
    }
    override func stopLoading() {}
}

@main struct CatalogChecks {
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: message, code: 1) }
    }

    static func main() async throws {
        let fixture = URL(filePath: CommandLine.arguments[1])
        let root = URL.temporaryDirectory.appending(path: "cottage-checks-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureProtocol.self]
        let session = URLSession(configuration: config)
        let data = try Data(contentsOf: fixture)
        let catalog = try JSONDecoder().decode(CottageCatalog.self, from: data).validated()
        let index = CottageCatalogIndex(catalog: catalog)
        try require(index.artists.count == 1 && index.artworks.count == 1, "Generated catalog must decode in the app")
        if CottageServiceConfiguration.publicRepository.isEmpty {
            try require(CottageServiceConfiguration.catalogURL == nil, "An empty repository must disable remote loading")
        }
        let entry = index.artworks[0]
        let files = entry.artwork.files!
        for file in files {
            // The Python fixture creates the same red PNG for each file.
            FixtureProtocol.responses[file.url.absoluteString] = try Data(contentsOf: fixture.deletingLastPathComponent().appending(path: "image.png"))
        }
        let endpoint = URL(string: "https://example.test/catalog.json")!
        FixtureProtocol.responses[endpoint.absoluteString] = data
        let repository = CottageCatalogRepository(cacheURL: root.appending(path: "catalog.json"), session: session)
        _ = try await repository.fetchCatalog(from: endpoint)
        let requestCount = FixtureProtocol.requests.count
        _ = try await repository.fetchCatalog(from: endpoint)
        try require(FixtureProtocol.requests.count == requestCount, "Recent catalog should not refetch")
        FixtureProtocol.responses[endpoint.absoluteString] = nil
        do {
            _ = try await repository.fetchCatalog(from: endpoint, force: true)
            throw NSError(domain: "Offline refresh should fail", code: 1)
        } catch let error as URLError { try require(error.code == .notConnectedToInternet, "Expected offline error") }
        let cached = await repository.cachedCatalog(for: endpoint)
        try require(cached?.catalog == catalog, "Offline refresh must preserve the last catalog")

        let downloadsRoot = root.appending(path: "packs")
        let downloads = CottageDownloads(directory: downloadsRoot, session: session)
        let pack = try await downloads.install(entry)
        let installed = try await downloads.installedPacks()
        try require(installed.count == 1, "Complete download must be visible")
        let imageURL = pack.fileURL(for: files[0], in: downloadsRoot)!
        try require(FileManager.default.fileExists(atPath: imageURL.path), "Downloaded file must persist")
        let preparedURL = try await downloads.stickerURL(for: files[0], in: pack)
        let preparedData = try Data(contentsOf: preparedURL)
        let imageSource = CGImageSourceCreateWithData(preparedData as CFData, nil)!
        let dimensions = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as! [CFString: Any]
        try require((dimensions[kCGImagePropertyPixelWidth] as! Int) <= 618 && (dimensions[kCGImagePropertyPixelHeight] as! Int) <= 618, "Messages copy must fit sticker dimensions")
        try require(preparedData.count <= 500_000, "Messages copy must fit sticker file size")
        let originalData = try Data(contentsOf: imageURL)
        let fixtureData = try Data(contentsOf: fixture.deletingLastPathComponent().appending(path: "image.png"))
        try require(originalData == fixtureData, "Preparing a sticker must preserve the original")
        let requestsBeforeReinstall = FixtureProtocol.requests.count
        _ = try await downloads.install(entry)
        try require(FixtureProtocol.requests.count == requestsBeforeReinstall, "Reinstall must reuse verified local files")

        var changedObject = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var artworks = changedObject["artworks"] as! [[String: Any]]
        var changedFiles = artworks[0]["files"] as! [[String: Any]]
        changedFiles[0]["sha256"] = String(repeating: "a", count: 64)
        artworks[0]["files"] = changedFiles
        changedObject["artworks"] = artworks
        let changed = try JSONDecoder().decode(CottageCatalog.self, from: JSONSerialization.data(withJSONObject: changedObject)).validated()
        let incomplete = try await downloads.reconcile(with: CottageCatalogIndex(catalog: changed))
        try require(incomplete.isEmpty, "Changed images must hide an incomplete pack")
        try require(!FileManager.default.fileExists(atPath: imageURL.path), "Old image must be purged")
        try require(!FileManager.default.fileExists(atPath: preparedURL.path), "Withdrawn Messages copy must also be purged")
        do {
            _ = try await downloads.install(CottageCatalogIndex(catalog: changed).artworks[0])
            throw NSError(domain: "Checksum mismatch should fail", code: 1)
        } catch CottageDownloadError.checksumMismatch {}
        let stillIncomplete = try await downloads.installedPacks()
        try require(stillIncomplete.isEmpty, "Failed download must not expose partial content")
        let empty = CottageCatalog(version: 1, artists: [], artworks: [])
        _ = try await downloads.reconcile(with: CottageCatalogIndex(catalog: empty))
        try require(!FileManager.default.fileExists(atPath: downloadsRoot.appending(path: CottageDownloads.directoryName(for: entry.id)).path), "Removed packs must be purged, including partial downloads")
        do {
            _ = try await CottageHTTP.data(from: files[0].url, maximumBytes: 1, session: session)
            throw NSError(domain: "Oversized response should fail", code: 1)
        } catch let error as URLError { try require(error.code == .dataLengthExceedsMaximum, "Expected size limit") }
        print("PASS: catalog interoperability, throttling, offline cache, local downloads, reuse, checksums, partial downloads, removals, response limits")
    }
}
