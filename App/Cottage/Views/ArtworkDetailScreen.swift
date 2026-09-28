import SwiftUI

struct ArtworkDetailScreen: View {
    let entry: CottageArtworkEntry
    @Environment(CottageStore.self) private var store

    private var current: CottageArtworkEntry? { store.index.artworks.first { $0.id == entry.id } }

    var body: some View {
        ScrollView {
            if let current {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ArtworkTitleSection(entry: current)
                    ArtworkCreditsSection(artists: current.creditedArtists, artistDirectory: store.index.artists)
                    ArtworkGallery(entry: current)
                    ArtworkActionsSection(entry: current)
                    CottageUsageSection(artists: current.creditedArtists)
                }
                .padding(20)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            } else {
                ContentUnavailableView("Collection Unavailable", systemImage: "photo.stack", description: Text("This collection is no longer available."))
            }
        }
        .background(CottageTheme.parchment)
        .navigationTitle(entry.artwork.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ArtworkTitleSection: View {
    let entry: CottageArtworkEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let collection = entry.artwork.collectionTitle {
                Text(collection).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(entry.artwork.title).font(.system(.largeTitle, design: .serif))
            CottageArtworkByline(artists: entry.creditedArtists).font(.subheadline)
            Text(entry.artwork.summary).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

private struct ArtworkCreditsSection: View {
    let artists: [CottageArtist]
    let artistDirectory: [CottageArtistEntry]
    var body: some View {
        VStack(spacing: 10) {
            ForEach(artists) { artist in
                NavigationLink {
                    if let entry = artistDirectory.first(where: { $0.id == artist.id }) {
                        ArtistDetailScreen(entry: entry)
                    }
                } label: {
                    HStack(spacing: 12) {
                        CottageArtistAvatar(artist: artist, size: 42)
                        Text(artist.displayName).font(.system(.headline, design: .serif))
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }.padding(12)
                    .background(CottageTheme.card, in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain)
            }
        }
    }
}

private struct ArtworkGallery: View {
    let entry: CottageArtworkEntry
    @Environment(CottageStore.self) private var store
    private var installed: CottageInstalledPack? { store.installedPacks.first { $0.id == entry.id } }
    private var files: [CottageMediaFile] {
        entry.artwork.deliveryKind == .cottage ? entry.artwork.files ?? [] : []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if files.isEmpty {
                CottageArtworkPreview(artwork: entry.artwork, cornerRadius: 22)
                    .aspectRatio(entry.artwork.kind == .stickerPack ? 1.3 : 0.8, contentMode: .fit)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: entry.artwork.kind == .stickerPack ? 84 : 135))], spacing: 16) {
                    ForEach(files) { file in
                        // Saved packs use local files and can be shared; others preview from the catalog.
                        if let installed, let url = installed.fileURL(for: file) {
                            ShareLink(item: url) { tile(url) }
                                .accessibilityLabel(Text("Share \(file.title) by \(entry.creditedArtists.map(\.displayName).formatted())"))
                        } else {
                            tile(file.url)
                                .accessibilityLabel(Text("\(file.title) by \(entry.creditedArtists.map(\.displayName).formatted())"))
                        }
                    }
                }
            }
            if installed != nil {
                Text("Tap an image to share or save it.").font(.caption).foregroundStyle(.secondary)
            } else if let count = entry.artwork.itemCount {
                Text("^[\(count) image](inflect: true) · Free")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func tile(_ url: URL) -> some View {
        CottageRemoteImage(url: url, fit: true)
            .aspectRatio(entry.artwork.kind == .stickerPack ? 1 : 0.65, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct ArtworkActionsSection: View {
    let entry: CottageArtworkEntry
    @Environment(CottageStore.self) private var store
    private var isInstalled: Bool { store.installedPacks.contains { $0.id == entry.id } }
    private var isDownloading: Bool { store.downloadingIDs.contains(entry.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isInstalled {
                Label("Saved to your Library", systemImage: "checkmark.circle.fill")
                    .font(.headline).foregroundStyle(CottageTheme.moss)
                if entry.artwork.kind == .stickerPack {
                    Text("Open Messages, tap +, then choose The Cottage to use this pack.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } else if entry.artwork.deliveryKind == .cottage {
                Button {
                    Task { await store.download(entry) }
                } label: {
                    HStack {
                        if isDownloading { ProgressView() }
                        Text(isDownloading ? "Adding pack…" : entry.artwork.kind == .stickerPack ? "Add to Messages" : "Add to Library")
                        if !isDownloading { Image(systemName: "arrow.down") }
                    }
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                .disabled(isDownloading || store.isRefreshing)
                Text("Free. Downloaded once, ready offline.").font(.caption).foregroundStyle(.secondary)
            } else {
                Label("Collection coming soon", systemImage: "leaf")
                    .font(.headline).foregroundStyle(CottageTheme.moss)
                Text("The artist's files and usage permissions are being prepared.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        if let entry = CottageCatalogIndex.empty.artworks.first {
            ArtworkDetailScreen(entry: entry)
        }
    }.environment(CottageStore())
}
