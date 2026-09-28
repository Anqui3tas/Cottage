import SwiftUI

private enum ArtistFilter: String, CaseIterable, Identifiable {
    case all, stickers, wallpapers
    var id: Self { self }
    var title: LocalizedStringResource {
        switch self {
        case .all: "All artists"
        case .stickers: "Stickers"
        case .wallpapers: "Wallpapers"
        }
    }
}

struct ArtistsScreen: View {
    let entries: [CottageArtistEntry]
    @Environment(CottageStore.self) private var store
    @State private var search = ""
    @State private var filter: ArtistFilter = .all

    private var visibleEntries: [CottageArtistEntry] {
        entries.filter { entry in
            let matchesKind = filter == .all || entry.artworks.contains {
                $0.artwork.kind == (filter == .stickers ? .stickerPack : .wallpaper)
            }
            let text = ([entry.artist.displayName, entry.artist.biography ?? ""]
                + entry.artworks.map { $0.artwork.title + " " + ($0.artwork.collectionTitle ?? "") }).joined(separator: " ")
            return matchesKind && (search.isEmpty || text.localizedStandardContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Small creations.\nA world of artists.")
                            .font(.system(.largeTitle, design: .serif))
                        Text("Find a little something that feels like you.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search artists or collections", text: $search)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                    }
                    .padding(13)
                    .background(CottageTheme.moss.opacity(0.06), in: Capsule())
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(ArtistFilter.allCases) { item in
                                Button { filter = item } label: {
                                    Text(item.title).font(.subheadline.weight(.medium))
                                        .padding(.horizontal, 18).padding(.vertical, 10)
                                        .foregroundStyle(filter == item ? CottageTheme.parchment : CottageTheme.moss)
                                        .background(filter == item ? CottageTheme.moss : CottageTheme.moss.opacity(0.06), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(filter == item ? .isSelected : [])
                            }
                        }
                    }.scrollIndicators(.hidden)
                    ArtistDirectorySection(entries: visibleEntries)
                    Text("Shared by artists. Free for everyone.")
                        .font(.system(.footnote, design: .serif).italic())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .padding(20)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(CottageTheme.parchment)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    CottageWordmark().dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                }
                CottageAboutToolbarItem()
            }
            .refreshable { await store.refresh(force: true) }
        }
    }
}

private struct ArtistDirectorySection: View {
    let entries: [CottageArtistEntry]
    @Environment(CottageStore.self) private var store

    var body: some View {
        VStack(spacing: 12) {
            if entries.isEmpty {
                if !store.index.artists.isEmpty {
                    ContentUnavailableView("No Artists Found", systemImage: "leaf", description: Text("Try another name or collection."))
                } else if store.isRefreshing {
                    ProgressView().padding(.vertical, 40)
                } else {
                    ContentUnavailableView("Artists Are on Their Way", systemImage: "leaf", description: Text("Pull down to check again."))
                }
            }
            ForEach(entries) { entry in
                NavigationLink {
                    ArtistDetailScreen(entry: entry)
                } label: {
                    ArtistDirectoryCard(entry: entry)
                }.buttonStyle(.plain)
            }
        }
    }
}

private struct ArtistDirectoryCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let entry: CottageArtistEntry
    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(spacing: 14))
        layout {
            CottageRemoteImage(url: entry.artist.headerURL ?? entry.artist.avatarURL, symbol: "leaf")
                .frame(width: 88, height: 106)
                .clipShape(RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.artist.displayName).font(.system(.title3, design: .serif).weight(.semibold))
                if let biography = entry.artist.biography {
                    Text(biography).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                }
                Text("^[\(entry.artworks.count) pack](inflect: true)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            Text("View").font(.caption.weight(.medium)).fixedSize()
                .padding(.horizontal, 13).padding(.vertical, 8)
                .background(CottageTheme.moss.opacity(0.06), in: Capsule())
        }
        .padding(10)
        .background(CottageTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

struct ArtistDetailScreen: View {
    let entry: CottageArtistEntry
    @Environment(CottageStore.self) private var store

    // Resolve the current profile so a catalog removal doesn't leave a stale download button.
    private var currentEntry: CottageArtistEntry? { store.index.artists.first { $0.id == entry.id } }

    var body: some View {
        ScrollView {
            if let currentEntry {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ArtistProfileHero(artist: currentEntry.artist)
                    if !currentEntry.artist.links.isEmpty {
                        ArtistLinksSection(links: currentEntry.artist.links)
                    }
                    ArtistWorksSection(entries: currentEntry.artworks)
                    CottageUsageSection(artists: [currentEntry.artist])
                }
                .padding(20)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            } else {
                ContentUnavailableView("Artist Unavailable", systemImage: "leaf", description: Text("This artist is no longer in the catalog."))
            }
        }
        .background(CottageTheme.parchment)
        .navigationTitle(entry.artist.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ArtistProfileHero: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let artist: CottageArtist
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            CottageRemoteImage(url: artist.headerURL, symbol: "leaf")
                .frame(height: 230)
                .clipShape(RoundedRectangle(cornerRadius: 22))
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
            layout {
                CottageArtistAvatar(artist: artist, size: 64)
                VStack(alignment: .leading, spacing: 8) {
                    Text(artist.displayName).font(.system(.title, design: .serif).weight(.semibold))
                    if let biography = artist.biography {
                        Text(biography).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct ArtistLinksSection: View {
    let links: [CottageArtistLink]
    var body: some View {
        VStack(spacing: 10) {
            ForEach(links) { link in
                Link(destination: link.url) {
                    HStack {
                        Image(systemName: "link")
                        Text(link.url.host() ?? String(localized: "Artist website"))
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption)
                    }
                    .font(.subheadline)
                    .padding(14)
                    .background(CottageTheme.card, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }
}

private struct ArtistWorksSection: View {
    let entries: [CottageArtworkEntry]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CottageSectionHeader(title: "Collections & packs", subtitle: "Little things, made to be shared.")
            if entries.isEmpty {
                Text("The first collection is on its way.").foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                NavigationLink {
                    ArtworkDetailScreen(entry: entry)
                } label: { CottageArtworkRow(entry: entry) }
                .buttonStyle(.plain)
            }
        }
    }
}

struct CottageUsageSection: View {
    let artists: [CottageArtist]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CottageSectionHeader(title: "Usage & credit", subtitle: "The art belongs to its creator.")
            ForEach(artists) { artist in
                VStack(alignment: .leading, spacing: 8) {
                    Text(artist.displayName).font(.headline)
                    Text(artist.usage ?? String(localized: "Usage permissions are being confirmed. Downloads will be available once the artist's terms are ready."))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(CottageTheme.card, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }
}

#Preview { ArtistsScreen(entries: CottageCatalogIndex.empty.artists).environment(CottageStore()) }
