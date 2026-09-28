import Foundation

actor CottageCatalogRepository {
    private struct SavedCatalog: Codable {
        let endpoint: URL
        let checkedAt: Date
        let catalog: CottageCatalog
    }

    private let cacheURL: URL
    private let session: URLSession

    init(cacheURL: URL = URL.applicationSupportDirectory.appending(path: "Cottage/catalog.json"), session: URLSession = .shared) {
        self.cacheURL = cacheURL
        self.session = session
    }

    func cachedCatalog(for endpoint: URL) -> CottageCatalogIndex? {
        guard let saved = savedCatalog(), saved.endpoint == endpoint,
              let catalog = try? saved.catalog.validated() else { return nil }
        return CottageCatalogIndex(catalog: catalog)
    }

    func fetchCatalog(from endpoint: URL, force: Bool = false) async throws -> CottageCatalogIndex {
        if !force, let saved = savedCatalog(), saved.endpoint == endpoint,
           Date().timeIntervalSince(saved.checkedAt) < CottageServiceConfiguration.catalogRefreshInterval {
            return CottageCatalogIndex(catalog: try saved.catalog.validated())
        }
        let data = try await CottageHTTP.data(from: endpoint, maximumBytes: 2_000_000, revalidate: true, session: session)
        let catalog = try JSONDecoder().decode(CottageCatalog.self, from: data).validated()
        let saved = SavedCatalog(endpoint: endpoint, checkedAt: Date(), catalog: catalog)
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(saved).write(to: cacheURL, options: .atomic)
        return CottageCatalogIndex(catalog: catalog)
    }

    private func savedCatalog() -> SavedCatalog? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(SavedCatalog.self, from: data)
    }
}
