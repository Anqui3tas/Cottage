import Foundation
import Observation

@MainActor @Observable
final class CottageStore {
    private(set) var index = CottageCatalogIndex.empty
    private(set) var installedPacks: [CottageInstalledPack] = []
    private(set) var downloadingIDs: Set<String> = []
    private(set) var isRefreshing = false
    var errorMessage: String?
    private var hasLoaded = false
    private let repository = CottageCatalogRepository()

    func refresh(force: Bool = false) async {
        guard !isRefreshing, downloadingIDs.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            if !hasLoaded {
                installedPacks = try await CottageDownloads.shared.installedPacks()
                if let endpoint = CottageServiceConfiguration.catalogURL,
                   let cached = await repository.cachedCatalog(for: endpoint) {
                    index = cached
                }
                hasLoaded = true
            }
            guard let endpoint = CottageServiceConfiguration.catalogURL else { return }
            let refreshed = try await repository.fetchCatalog(from: endpoint, force: force)
            installedPacks = try await CottageDownloads.shared.reconcile(with: refreshed)
            index = refreshed
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            // Automatic checks fail quietly so saved content stays usable offline.
            guard !Task.isCancelled, force else { return }
            errorMessage = String(localized: "Couldn't refresh collections. Your saved artwork is still available. \(error.localizedDescription)")
        }
    }

    func download(_ entry: CottageArtworkEntry) async {
        guard !isRefreshing, !downloadingIDs.contains(entry.id) else { return }
        guard index.artworks.contains(where: { $0 == entry }), entry.artwork.deliveryKind == .cottage else {
            errorMessage = String(localized: "This collection has changed. Return to the artist's profile and try again.")
            return
        }
        downloadingIDs.insert(entry.id)
        defer { downloadingIDs.remove(entry.id) }
        do {
            let pack = try await CottageDownloads.shared.install(entry)
            installedPacks.removeAll { $0.id == pack.id }
            installedPacks.append(pack)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func remove(_ pack: CottageInstalledPack) async {
        do {
            try await CottageDownloads.shared.remove(pack.id)
            installedPacks.removeAll { $0.id == pack.id }
        } catch { errorMessage = error.localizedDescription }
    }
}
